#
# Makefile for isolation tests
#

subdir = src/test/isolation
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# where to find psql for testing an existing installation
PSQLDIR = $(bindir)

override CPPFLAGS := -I$(srcdir) -I$(libpq_srcdir) -I$(srcdir)/../regress $(CPPFLAGS)

ifneq "$(MAKECMDGOALS)" "clean"
  ifneq "$(MAKECMDGOALS)" "distclean"
    ifneq "$(shell which g++ |grep hutaf_llt |wc -l)" "1"
      -include $(DEPEND)
    endif
  endif
endif
OBJS =  specparse.o isolationtester.o

all: isolationtester$(X) pg_isolation_regress$(X)

submake-regress:
	$(MAKE) -C $(top_builddir)/src/test/regress pg_regress.o

pg_regress.o: | submake-regress
	rm -f $@ && $(LN_S) $(top_builddir)/src/test/regress/pg_regress.o .

pg_isolation_regress$(X): isolation_main.o pg_regress.o
	$(CC) $(CFLAGS) $^ $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@

isolationtester$(X): $(OBJS) | submake-libpq submake-libpgport
	$(CC) $(CFLAGS) $^ $(libpq_pgport) $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@

distprep: specparse.cpp specscanner.cpp

# There is no correct way to write a rule that generates two files.
# Rules with two targets don't have that meaning, they are merely
# shorthand for two otherwise separate rules.  To be safe for parallel
# make, we must chain the dependencies like this.  The semicolon is
# important, otherwise make will choose the built-in rule for
# gram.y=>gram.cpp.

specparse.h: specparse.cpp ;

# specscanner is compiled as part of specparse
specparse.o: specscanner.cpp

specparse.cpp: specparse.y
ifdef BISON
	$(BISON) $(BISONFLAGS) -o $@ $<
else
	@$(missing) bison $< $@
endif

specscanner.cpp: specscanner.l
ifdef FLEX
	$(FLEX) $(FLEXFLAGS) -o'$@' $<
else
	@$(missing) flex $< $@
endif

# specparse.cpp and specscanner.cpp are in the distribution tarball,
# so do not clean them here
clean distclean:
	rm -f isolationtester$(X) pg_isolation_regress$(X) $(OBJS) isolation_main.o *.depend
	rm -f pg_regress.o
	rm -rf $(pg_regress_clean_files)

maintainer-clean: distclean
	rm -f specparse.cpp specscanner.cpp

installcheck: all
	./pg_isolation_regress --psqldir='$(PSQLDIR)' --inputdir=$(srcdir) --schedule=$(srcdir)/isolation_schedule

check: all
	./pg_isolation_regress --temp-install=./tmp_check --inputdir=$(srcdir) --top-builddir=$(top_builddir) --schedule=$(srcdir)/isolation_schedule

# Versions of the check tests that include the prepared_transactions test
# It only makes sense to run these if set up to use prepared transactions,
# via TEMP_CONFIG for the check case, or via the postgresql.conf for the
# installcheck case.
installcheck-prepared-txns: all
	./pg_isolation_regress --psqldir='$(PSQLDIR)' --inputdir=$(srcdir) --schedule=$(srcdir)/isolation_schedule prepared-transactions

check-prepared-txns: all
	./pg_isolation_regress --temp-install=./tmp_check --inputdir=$(srcdir) --top-builddir=$(top_builddir) --schedule=$(srcdir)/isolation_schedule prepared-transactions
