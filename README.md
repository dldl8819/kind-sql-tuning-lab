# 친절한 SQL 튜닝 실습 (Oracle XE 21c)

## 목적
- SQL 처리 과정(파싱/최적화/실행) 관점에서 실습으로 감 잡기
- 실행계획/통계/힌트가 옵티마이저 선택에 미치는 영향 확인

## 환경
- Oracle Database XE 21c

## 빠른 시작
1) 사용자/권한/QUOTA 설정
```sql
@sql/01-schema/010_create_user.sql
@sql/01-schema/020_grants.sql
@sql/01-schema/030_quota.sql
