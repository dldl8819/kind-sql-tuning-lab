# 실습 실행 순서 (Runbook)

## 1. 관리자 계정 접속
```bash
sqlplus system/<PASSWORD>@localhost:1521/XEPDB1
```

## 2. 실습 계정 및 권한 설정
@sql/01-schema/010_create_user.sql
@sql/01-schema/020_grants.sql
@sql/01-schema/030_quota.sql

## 3. 실습 계정 접속
```bash
sqlplus tuning/tuning@localhost:1521/XEPDB1
```

## 4. 테이블 생성 
@sql/02-ddl/010_create_dept.sql
@sql/02-ddl/020_create_emp.sql

## 5. 데이터 적재
@sql/03-dml/010_insert_dept.sql
@sql/03-dml/020_insert_emp.sql

## 6. 기본 실행계획 실습
@sql/04-plan/010_join_order_by.sql

