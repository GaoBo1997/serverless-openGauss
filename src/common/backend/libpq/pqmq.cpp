/*-------------------------------------------------------------------------
 *
 * pqmq.cpp
 *    Use the frontend/backend protocol for communication over a shm_mq
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *  src/common/backend/libpq/pqmq.cpp
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "libpq/libpq.h"
#include "libpq/pqformat.h"
#include "libpq/pqmq.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "tcop/tcopprot.h"
#include "utils/builtins.h"

static void mq_comm_reset(void);
static int  mq_flush(void);
static int  mq_flush_if_writable(void);
static bool mq_is_send_pending(void);
static int  mq_putmessage(char msgtype, const char *s, size_t len);
static int mq_putmessage_noblock(char msgtype, const char *s, size_t len);
static void mq_startcopyout(void);
static void mq_endcopyout(bool errorAbort);

static const PQcommMethods PqCommMqMethods = {
    mq_comm_reset,
    mq_flush,
    mq_flush_if_writable,
    mq_is_send_pending,
    mq_putmessage,
    mq_putmessage_noblock,
    mq_startcopyout,
    mq_endcopyout
};

/*
 * Arrange to redirect frontend/backend protocol messages to a message queue.
 */
void pq_redirect_to_shm_mq(shm_mq_handle *mqh)
{
	t_thrd.msqueue_cxt.save_PqCommMethods = t_thrd.msqueue_cxt.PqCommMethods;
	t_thrd.msqueue_cxt.save_whereToSendOutput = CommandDest(t_thrd.postgres_cxt.whereToSendOutput);
	t_thrd.msqueue_cxt.save_FrontendProtocol = FrontendProtocol;

	t_thrd.msqueue_cxt.PqCommMethods = &PqCommMqMethods;
    t_thrd.msqueue_cxt.pq_mq = shm_mq_get_queue(mqh);
	t_thrd.msqueue_cxt.pq_mq_handle = mqh;
	t_thrd.postgres_cxt.whereToSendOutput = static_cast<int>(DestRemote);
	FrontendProtocol = PG_PROTOCOL_LATEST;
    t_thrd.msqueue_cxt.is_changed = true;
}

void pq_stop_redirect_to_shm_mq(void)
{
    t_thrd.msqueue_cxt.PqCommMethods = t_thrd.msqueue_cxt.save_PqCommMethods;
    t_thrd.postgres_cxt.whereToSendOutput = static_cast<int>(t_thrd.msqueue_cxt.save_whereToSendOutput);
    FrontendProtocol = t_thrd.msqueue_cxt.save_FrontendProtocol;
    t_thrd.msqueue_cxt.pq_mq = NULL;
    t_thrd.msqueue_cxt.pq_mq_handle = NULL;
    t_thrd.msqueue_cxt.is_changed = false;
}

/*
 * Arrange to SendProcSignal() to the parallel master each time we transmit
 * message data via the shm_mq.
 */
void pq_set_parallel_master(ThreadId pid, BackendId backend_id)
{
    Assert(t_thrd.msqueue_cxt.PqCommMethods == &PqCommMqMethods);
    t_thrd.msqueue_cxt.pq_mq_parallel_master_pid = pid;
    t_thrd.msqueue_cxt.pq_mq_parallel_master_backend_id = backend_id;
}

static void mq_comm_reset(void)
{
    /* Nothing to do. */
}

static int mq_flush(void)
{
    /* Nothing to do. */
    return 0;
}

static int mq_flush_if_writable(void)
{
    /* Nothing to do. */
    return 0;
}

static bool mq_is_send_pending(void)
{
    /* There's never anything pending. */
    return false;
}

/*
 * Transmit a libpq protocol message to the shared memory message queue
 * selected via pq_mq_handle.  We don't include a length word, because the
 * receiver will know the length of the message from shm_mq_receive().
 */
static int mq_putmessage(char msgtype, const char *s, size_t len)
{
    shm_mq_iovec iov[2];
    shm_mq_result result;

    /*
     * If we're sending a message, and we have to wait because the queue is
     * full, and then we get interrupted, and that interrupt results in trying
     * to send another message, we respond by detaching the queue.  There's no
     * way to return to the original context, but even if there were, just
     * queueing the message would amount to indefinitely postponing the
     * response to the interrupt.  So we do this instead.
     */
    if (t_thrd.msqueue_cxt.pq_mq_busy) {
        if (t_thrd.msqueue_cxt.pq_mq_handle != NULL)
            shm_mq_detach(t_thrd.msqueue_cxt.pq_mq_handle);
        t_thrd.msqueue_cxt.pq_mq_handle = NULL;
        return EOF;
    }

    /*
     * If the message queue is already gone, just ignore the message. This
     * doesn't necessarily indicate a problem; for example, DEBUG messages can
     * be generated late in the shutdown sequence, after all DSMs have already
     * been detached.
     */
    if (t_thrd.msqueue_cxt.pq_mq_handle == NULL)
        return 0;

    t_thrd.msqueue_cxt.pq_mq_busy = true;

    iov[0].data = &msgtype;
    iov[0].len = 1;
    iov[1].data = s;
    iov[1].len = len;

    Assert(t_thrd.msqueue_cxt.pq_mq_handle != NULL);

    for (;;) {
        result = shm_mq_sendv(t_thrd.msqueue_cxt.pq_mq_handle, iov, 2, true);

        if (t_thrd.msqueue_cxt.pq_mq_parallel_master_pid != 0)
            (void)SendProcSignal(t_thrd.msqueue_cxt.pq_mq_parallel_master_pid,PROCSIG_PARALLEL_MESSAGE,
                                 t_thrd.msqueue_cxt.pq_mq_parallel_master_backend_id);

        if (result != SHM_MQ_WOULD_BLOCK)
            break;

        (void)WaitLatch(&t_thrd.proc->procLatch, WL_LATCH_SET, 0);
        ResetLatch(&t_thrd.proc->procLatch);
        CHECK_FOR_INTERRUPTS();
    }

    t_thrd.msqueue_cxt.pq_mq_busy = false;

    Assert(result == SHM_MQ_SUCCESS || result == SHM_MQ_DETACHED);
    if (result != SHM_MQ_SUCCESS)
        return EOF;
    return 0;
}

static int mq_putmessage_noblock(char msgtype, const char *s, size_t len)
{
    /*
     * While the shm_mq machinery does support sending a message in
     * non-blocking mode, there's currently no way to try sending beginning to
     * send the message that doesn't also commit us to completing the
     * transmission.  This could be improved in the future, but for now we
     * don't need it.
     */
    elog(ERROR, "not currently supported");
    return 0;
}

static void mq_startcopyout(void)
{
    /* Nothing to do. */
}

static void mq_endcopyout(bool errorAbort)
{
    /* Nothing to do. */
}

/*
 * Parse an ErrorResponse or NoticeResponse payload and populate an ErrorData
 * structure with the results.
 */
void pq_parse_errornotice(StringInfo msg, ErrorData *edata)
{
    /* Initialize edata with reasonable defaults. */
    errno_t rc = memset_s(edata, sizeof(ErrorData), 0, sizeof(ErrorData));
    securec_check(rc, "\0", "\0");
    edata->elevel = ERROR;

    /* Loop over fields and extract each one. */
    for (;;) {
        char code = pq_getmsgbyte(msg);
        const char *value = NULL;

        if (code == '\0') {
            pq_getmsgend(msg);
            break;
        }
        value = pq_getmsgrawstring(msg);

        switch (code) {
            case PG_DIAG_SEVERITY:
                /* ignore, trusting we'll get a nonlocalized version */
                break;
            case PG_DIAG_INTERNEL_ERRCODE:
                /* ignore */
                break;
            case PG_DIAG_MODULE_ID:
                /* It is always MOD_MAX */
                edata->mod_id = MOD_MAX;
                break;
            case PG_DIAG_SQLSTATE:
                if (strlen(value) != 5) {
                    elog(ERROR, "invalid SQLSTATE: \"%s\"", value);
                }
                edata->sqlerrcode = MAKE_SQLSTATE(value[0], value[1], value[2],
                                                  value[3], value[4]);
                break;
            case PG_DIAG_MESSAGE_PRIMARY:
                edata->message = pstrdup(value);
                break;
            case PG_DIAG_MESSAGE_DETAIL:
                edata->detail = pstrdup(value);
                break;
            case PG_DIAG_MESSAGE_HINT:
                edata->hint = pstrdup(value);
                break;
            case PG_DIAG_STATEMENT_POSITION:
                edata->cursorpos = pg_atoi(const_cast<char*>(value), sizeof(int), '\0');
                break;
            case PG_DIAG_INTERNAL_POSITION:
                edata->internalpos = pg_atoi(const_cast<char*>(value), sizeof(int), '\0');
                break;
            case PG_DIAG_INTERNAL_QUERY:
                edata->internalquery = pstrdup(value);
                break;
            case PG_DIAG_CONTEXT:
                edata->context = pstrdup(value);
                break;
            case PG_DIAG_SOURCE_FILE:
                edata->filename = pstrdup(value);
                break;
            case PG_DIAG_SOURCE_LINE:
                edata->lineno = pg_atoi(const_cast<char*>(value), sizeof(int), '\0');
                break;
            case PG_DIAG_SOURCE_FUNCTION:
                edata->funcname = pstrdup(value);
                break;
            default:
                elog(ERROR, "unrecognized error field code: %d", (int) code);
                break;
        }
    }
}

