# 테이블 스페이스 사용 권한 부여
ALTER USER tuning QUOTA UNLIMITED ON USERS;
# 용량 제한 주기
ALTER USER tuning QUOTA 100M ON USERS;