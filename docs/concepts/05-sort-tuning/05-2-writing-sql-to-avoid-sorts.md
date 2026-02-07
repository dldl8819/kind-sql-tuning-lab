# 5.2 소트가 발생하지 않도록 SQL 작성
- 소트는 CPU와 메모리를 많이 사용하고, 데이터 양이 많을수록 TEMP 사용량까지 증가시킨다. 
- 따라서 SQL을 작성할 때 결과 집합의 의미를 유지하면서 불필요한 소트 연산을 피하는 방향으로 작성하는 것이 중요하다.
- Union, Minus, Distinct 연산자는 중복 레코드를 제거하기 위한 소트 연산을 발생시키므로 꼭 필요한 경우에만 사용해야 한다.
    - 성능이 느리다면 소트 연산을 피할 방법을 찾아봐야 한다.
    - 조인 방식도 잘 선택해줘야 한다.

## 5.2.1 Union vs. Union All
- SQL에 `Union`을 사용하면 옵티마지어는 두 집합 간 중복을 제거하기 위해 소트 작업을 수행한다.
- `Union All`은 중복을 확인하지 않고 두 집합을 단순히 결합하여 소트 작업을 수행하지 않는다.
    - 따라서 될 수 있으면 소트 부하를 줄일 수 있는 Union All을 사용해야 한다.
- Union을 Union All로 변경하려다 결과 집합이 달라질 수 있으므로 데이터 모델에 대한 이해와 집합적 사고가 필요하다.

### 1) 상호배타 조건이면 `UNION ALL` 사용

아래처럼 결제수단코드를 서로 다르게 조건으로 주면 두 집합은 절대 겹치지 않는다.

```sql
SELECT 결제번호, 주문번호, 결제금액, 주문일자
FROM   결제
WHERE  결제수단코드 = 'M'
AND    결제일자 = '20180316'
UNION
SELECT 결제번호, 주문번호, 결제금액, 주문일자
FROM   결제
WHERE  결제수단코드 = 'C'
AND    결제일자 = '20180316';
```

- 이 경우 `UNION`을 사용하면 불필요한 `SORT (UNIQUE)`가 발생한다. 
- 조건이 상호배타적임이 명확하다면 다음처럼 `UNION ALL`이 적절하다.

```sql
select 결제번호, 주문번호, 결제금액, 주문일자
from 결제
where 결제수단코드 = 'M'
  and 결제일자 = '20180316'
union all
select 결제번호, 주문번호, 결제금액, 주문일자
from 결제
where 결제수단코드 = 'C'
  and 결제일자 = '20180316';
```

핵심 판단 기준은 "두 집합이 물리적으로 겹칠 가능성이 0인가"이다.

### 2) 겹칠 수 있는 조건이면 중복 방지 조건을 함께 사용

아래 SQL은 결제일자와 주문일자 조건으로 집합을 나누므로 동일 행이 양쪽에 동시에 포함될 수 있다.

```sql
select 결제번호, 결제수단코드, 주문번호, 결제금액, 결제일자, 주문일자
from 결제
where 결제일자 = '20180316'
union
select 결제번호, 결제수단코드, 주문번호, 결제금액, 결제일자, 주문일자
from 결제
where 주문일자 = '20180316';
```

이때 `UNION ALL`로 단순 변경하면 중복 행이 그대로 출력된다. 소트 없이 중복을 피하려면 하단 집합에서 상단 집합과의 교집합을 제거하는 조건을 추가한다.

```sql
select 결제번호, 결제수단코드, 주문번호, 결제금액, 결제일자, 주문일자
from 결제
where 결제일자 = '20180316'
union all
select 결제번호, 결제수단코드, 주문번호, 결제금액, 결제일자, 주문일자
from 결제
where 주문일자 = '20180316'
  and 결제일자 <> '20180316';
```

위와 같이 교집합 제거 조건을 추가하면 실행계획은 `UNION-ALL` 중심으로 단순해지고, `SORT (UNIQUE)`가 사라진다.

```text
Execution Plan
----------------------------------------------------------
0  SELECT STATEMENT Optimizer=ALL_ROWS (Cost=0 Card=2 Bytes=106)
1    UNION-ALL
2      TABLE ACCESS (BY INDEX ROWID) OF '결제' (TABLE)
3        INDEX (RANGE SCAN) OF '결제_N2' (INDEX)
4      TABLE ACCESS (BY INDEX ROWID) OF '결제' (TABLE)
5        INDEX (RANGE SCAN) OF '결제_N3' (INDEX)
```

단, `결제일자`가 `NULL` 허용 컬럼이라면 `결제일자 <> '20180316'` 조건만으로는 `NULL` 데이터를 올바르게 처리하지 못할 수 있다. 이 경우 아래처럼 조건을 보완한다.

```sql
and (결제일자 <> '20180316' or 결제일자 is null)
```

또는 Oracle에서 `LNNVL` 함수를 사용해 동일한 의미로 표현할 수 있다.

```sql
and lnnvl(결제일자 = '20180316')
```

요약하면 다음과 같다.

- 중복 가능성 없음: `UNION ALL`
- 중복 가능성 있음: `UNION` 또는 `UNION ALL + 교집합 제거 조건`

`DISTINCT`, `UNION`, `IN` 서브쿼리 등은 중복 제거 또는 집합 연산 과정에서 소트를 유발할 수 있다. 조인 목적이 "존재 여부 확인"이라면 `EXISTS`로 작성해 불필요한 중복 확장과 소트 가능성을 줄이는 것이 효과적이다.

예를 들어 주문 테이블에서 결제가 한 건이라도 있는 주문만 조회하려면, 결제 행을 모두 조인해 중복을 만든 뒤 제거하기보다 `EXISTS`로 존재만 확인하는 형태가 유리하다.

```sql
select o.주문번호, o.고객번호, o.주문일자
from 주문 o
where exists (
    select 1
    from 결제 p
    where p.주문번호 = o.주문번호
);
```

`EXISTS`는 조건을 만족하는 행을 하나라도 찾으면 탐색을 멈출 수 있어, 데이터가 많은 환경에서 정렬/해시 부하를 줄이는 데 도움이 된다.
## 5.2.2 Exists 활용
- 중복 레코드 제거를 위해 `DISTINCT` 연산자를 자주 사용하지만, 조건에 해당하는 데이터를 모두 읽은 뒤 중복을 제거해야 하므로 부분범위 처리가 불가능하고 I/O가 증가하기 쉽다.
- 상품과 계약 테이블이 있고, 계약 인덱스가 `상품번호 + 계약일자`로 구성되어 있으면 상품 수는 적고 상품별 계약 건수가 많으면 비효율이 커진다.

### 1) `DISTINCT + 조인` 방식 (튜닝 전)

```sql
SELECT DISTINCT p.상품번호, p.상품명, p.상품가격, ...
FROM   상품 p, 계약 c
WHERE  p.상품유형코드 = :pclscd
AND    c.상품번호 = p.상품번호
AND    c.계약일자 BETWEEN :dt1 AND :dt2
AND    c.계약구분코드 = :ctpcd
```

```
Execution Plan
----------------------------------------------------------
0    SELECT STATEMENT Optimizer=ALL_ROWS (Cost=3 Card=1 Bytes=80)
1  0   HASH (UNIQUE) (Cost=3 Card=1 Bytes=80)
2  1     FILTER
3  2      NESTED LOOPS
4  3       NESTED LOOPS (Cost=2 Card=1 Bytes=80)
5  4          TABLE ACCESS (BY INDEX ROWID) OF '상품' (TABLE) (Cost=1 ...)
6  5            INDEX (RANGE SCAN) OF '상품_X1' (INDEX) (Cost=1 Card=1)
7  4          INDEX (RANGE SCAN) OF '계약_X2' (INDEX) (Cost=1 Card=1)
8  3        TABLE ACCESS (BY INDEX ROWID) OF '계약' (TABLE) (Cost=1 ...)
```

### 2) `EXISTS` 방식으로 변경 (튜닝 후)

```sql
SELECT p.상품번호, p.상품명, p.상품가격, ...
FROM   상품 p
WHERE  p.상품유형코드 = :pclscd
AND    EXISTS (
         SELECT 'x'
         FROM   계약 c
         WHERE  c.상품번호 = p.상품번호
         AND    c.계약일자 BETWEEN :dt1 AND :dt2
         AND    c.계약구분코드 = :ctpcd
       )
```

```
Execution Plan
----------------------------------------------------------
0    SELECT STATEMENT Optimizer=ALL_ROWS (Cost=2 Card=1 Bytes=80)
1  0   FILTER
2  1    NESTED LOOPS (SEMI) (Cost=2 Card=1 Bytes=80)
3  2      TABLE ACCESS (BY INDEX ROWID) OF '상품' (TABLE) (Cost=1 Card=1 ...)
4  3        INDEX (RANGE SCAN) OF '상품_X1' (INDEX) (Cost=1 Card=1)
5  2      TABLE ACCESS (BY INDEX ROWID) OF '계약' (TABLE) (Cost=1 Card=1 ...)
6  5        INDEX (RANGE SCAN) OF '계약_X2' (INDEX) (Cost=1 Card=1)
```

- `EXISTS` 서브쿼리는 데이터 존재 여부만 확인하면 되니 조건을 만족하는 데이터를 모두 읽지 않고 계약 1건을 찾는 즉시 멈출 수 있다.
  - 부분범위 처리 가능


### 3) `MINUS`도 `NOT EXISTS`로 튜닝
- 튜닝 전: `A MINUS B`
- 튜닝 후: `A WHERE NOT EXISTS`
```sql
-- 튜닝 전 예시
SELECT ST.상황접수번호, ST.관제일련번호, ST.상황코드, ST.관제일시
FROM   관제진행상황 ST
WHERE  상황코드 = '0001'
AND    관제일시 BETWEEN :V_TIMEFROM || '000000' AND :V_TIMETO || '235959'
MINUS
SELECT ST.상황접수번호, ST.관제일련번호, ST.상황코드, ST.관제일시
FROM   관제진행상황 ST, 구조활동 RPT
WHERE  상황코드 = '0001'
AND    관제일시 BETWEEN :V_TIMEFROM || '000000' AND :V_TIMETO || '235959'
AND    RPT.출동센터ID = :V_CNTR_ID
AND    ST.상황접수번호 = RPT.상황접수번호
ORDER BY 상황접수번호, 관제일시
```
```sql
-- 튜닝 후 예시
SELECT ST.상황접수번호, ST.관제일련번호, ST.상황코드, ST.관제일시
FROM   관제진행상황 ST
WHERE  상황코드 = '0001'
AND    관제일시 BETWEEN :V_TIMEFROM || '000000' AND :V_TIMETO || '235959'
AND    NOT EXISTS (
         SELECT 'X'
         FROM   구조활동
         WHERE  출동센터ID = :V_CNTR_ID
         AND    상황접수번호 = ST.상황접수번호
       )
ORDER BY ST.상황접수번호, ST.관제일시
```
## 5.2.3 조인 방식 변경
- 계약 인덱스가 `계약_X01(지점ID + 계약일시)` 순이면 소트 연산을 생략할 수 있지만, 해시 조인이기 때문에 `SORT ORDER BY`가 나타난다.

```sql
SELECT c.계약번호, c.상품코드, p.상품명, p.상품구분코드, c.계약일시, c.계약금액
FROM   계약 c, 상품 p
WHERE  c.지점ID = :brch_id
AND    p.상품코드 = c.상품코드
ORDER BY c.계약일시 DESC
```

```
Execution Plan
----------------------------------------------------------
0    SELECT STATEMENT Optimizer=ALL_ROWS
1  0    SORT (ORDER BY)
2  1      HASH JOIN
3  2        TABLE ACCESS (FULL) OF '상품' (TABLE)
4  2        TABLE ACCESS (BY INDEX ROWID) OF '계약' (TABLE)
5  4          INDEX (RANGE SCAN) OF '계약_X01' (INDEX)
```

- 계약 테이블을 기준으로 상품 테이블과 `NL JOIN`하도록 조인 방식을 바꾸면, 소트 연산을 생략할 수 있다.
- 지점ID 조건을 만족하는 데이터가 부분범위 처리가 가능한 상황에서 성능 개선 효과가 크다.

```sql
SELECT /*+ LEADING(c) USE_NL(p) */
       c.계약번호, c.상품코드, p.상품명, p.상품구분코드, c.계약일시, c.계약금액
FROM   계약 c, 상품 p
WHERE  c.지점ID = :brch_id
AND    p.상품코드 = c.상품코드
ORDER BY c.계약일시 DESC
```

```
Execution Plan
----------------------------------------------------------
0    SELECT STATEMENT Optimizer=ALL_ROWS
1  0   NESTED LOOPS
2  1     NESTED LOOPS
3  2       TABLE ACCESS (BY INDEX ROWID) OF '계약' (TABLE)
4  3         INDEX (RANGE SCAN DESCENDING) OF '계약_X01' (INDEX)
5  2       INDEX (UNIQUE SCAN) OF '상품_PK' (INDEX (UNIQUE))
6  1     TABLE ACCESS (BY INDEX ROWID) OF '상품' (TABLE)
```

- 정렬 기준이 조인 키 컬럼이면 소트 머지 조인에서도 `SORT ORDER BY` 연산을 생략할 수 있다.
