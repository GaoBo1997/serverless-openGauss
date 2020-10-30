create role test_myrole001 with password "ttest@123";
create role test_myrole002 with sysadmin password "ttest@123";

-- test "SET ROLE role_name PASSWORD 'passwd'" in loop
BEGIN
	FOR i in 1..5 LOOP
		SET ROLE test_myrole001 PASSWORD 'ttest@123';
		RESET ROLE;
		SET ROLE test_myrole002 PASSWORD 'ttest@123';
		RESET ROLE;
	END LOOP;
END;
/

set role test_myrole001  password "ttest@123";
alter role test_myrole002 SET maintenance_work_mem = 100000; 
alter role test_myrole002 rename to temp_myrole;
reset role;
drop role test_myrole001;
drop role test_myrole002;
