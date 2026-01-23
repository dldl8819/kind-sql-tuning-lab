# 2.3 인덱스 확장기능 사용법
## 2.3.1 Index Range Scan
- B*Tree 인덱스의 가장 일반적이고 정상적인 형태의 액세스 방식
- 인덱스 루트에서 리프 블록까지 수직적 탐색 후 `필요한 범위(Range)만` 스캔
- 실행계획
    ```SQL
    set autotrace traceonly exp
    ```
    ```SQL
    select * from emp where deptno = 20;
    ```
    ```
    Execution Plan
    ------------------------------------------------------
    0     SELECT STATEMENT Optimizer=ALL_ROWS
    1   0  TABLE ACCESS (BY INDEX ROWID) OF 'EMP' (TABLE)
    2   1   INDEX (RANGE SCAN) OF 'EMP_DEPTNO_IDX' (INDEX)
    ```
    - 인덱스 잘 타니까 성능도 좋겠지 생각하면 안되고 인덱스 스캔 범위와 테이블 액세스 횟수를 얼마나 줄일 수 있는지 확인해야 한다.
- Index Range Scan은 선두 컬럼을 가공하지 않은 상태로 조건절에 사용해야 한다.
    - 선두 컬럼을 가공하지 않은 상태로 조건절에 사용하면 Index Range Scan이 무조건 가능

## 2.3.2 Index Full Scan
- 수직적 탐색없이 인덱스 리프 블록을 처음부터 끝까지 수평적으로 탐색
- 실행계획
    ```SQL
    create index emp_ename_sal_idx on emp (ename, sal);
    ```
    ```SQL
    set autotrace traceonly exp
    ```
    ```SQL
    select * from emp
    where sal > 2000
    order by ename;
    ```    
    ```
    Execution Plan
    ------------------------------------------------------
    0     SELECT STATEMENT Optimizer=ALL_ROWS
    1   0  TABLE ACCESS (BY INDEX ROWID) OF 'EMP' (TABLE)
    2   1   INDEX (FULL SCAN) OF 'EMP_ENAME_SAL_IDX' (INDEX)
    ```
    - 인덱스 선두 컬럼인 ename이 조건절에 없으므로 Index Range Scan 불가
    - SAL 컬럼이 인덱스에 뒤쪽에나마 있어서 Index Full Scan으로 SAL이 2000보다 큰 레코드를 찾을 수 있음
- 데이터 검색을 위한 최적의 인덱스가 없을 때 차선으로 선택됨
> Index Full Scan의 효용성
- 데이터 저장공간은 `가로 * 세로` 즉, `컬럼 길이 * 레코드 수`에 의해 결정되므로 인덱스가 차지하는 면적은 테이블보다 훨씬 작다.
- 인덱스 스캔 단계에서 대부분 레코드를 필터링하고 아주 일부만 테이블을 액세스하는 상황이라면, 면적이 큰 테이블보다 인덱스를 스캔하는 쪽이 유리하다.
> 인덱스를 이용한 소트 연산 생략
- Index Full Scan도 Range Scan과 마찬가지로 결과집합이 인덱스 컬럼 순으로 정렬되어 Sort Order By 연산을 생략할 목적으로 사용 가능하다.
    - 차선책이 아니라 옵티마이저가 전략적으로 선택한 경우에 해당    
    ```SQL
    select   /*+ first_rows */ * 
    from     emp
    where    sal > 1000
    order by ename;
    ```
    ```
    Execution Plan
    -------------------------------------------------
    0     SELECT STATEMENT Optimizer=HINT: FIRST_ROWS
    1   0  TABLE ACCESS (BY INDEX ROWID) OF 'EMP' (TABLE)
    2   1   INDEX (FULL SCAN) OF 'EMP_ENAME_SAL_IDX' (INDEX)
    ```
    - 소트 연산을 생략하여 전체 집합 중 처음 일부를 빠르게 출력할 목적으로 first_rows 힌트를 사용하여 Index Full Scan 방식 선택
    - 부분 범위 처리 활용 의도와 달리 fetch를 멈추지 않고 데이터를 끝까지 읽으면 Table Full Scan보다 더 많은 I/O를 일으켜 수행 속도도 훨씬 더 느려진다.
## 2.3.3 Index Unique Scan
- 수직적 탐색만으로 데이터를 찾는 스캔 방식
- Unique 인덱스를 `=` 조건으로 탐색하는 경우에 작동
    ```SQL
    create unique index pk_emp on emp(empno);
    ```
    ```SQL
    alter table emp add constraint pk_emp primary key(empno) using empno = 7788;
    ```
    ```SQL
    set autotrace traceonly explain
    ```
    ```SQL
    select empno, ename from emp where empno = 7788;
    ```
    ```
    Execution Plan
    -----------------------------------------------------------
    0    SELECT STATEMENT Optimizer=ALL_ROWS
    1  0  TABLE ACCESS (BY INDEX ROWID) OF 'EMP'
    2  1   INDEX (UNIQUE SCAN) OF 'PK_EMP' (UNIQUE)
    ```
    - Unique 인덱스가 존재하는 컬럼은 중복 값이 입력되지 않게 DBMS가 데이터 정합성을 관리
    - 해당 인덱스 키 컬럼을 모두 `=` 조건으로 검색할 때는 데이터를 한 건 찾는 순간 더 이상 탐색하지 않음
    - 범위검색 조건으로 검색할 때는 Unique 인덱스라고 해도 Index Range Scan으로 처리
        - empno >= 7788 조건 검색 시 수직적 탐색만으로는 조건에 해당하는 레코드를 모두 찾을 수 없음
    - 일부 컬럼만으로 검색할 때도 Unique 결합 인덱스에 대해 Index Range Scan으로 처리
        - 주문상품 PK 인덱스가 `주문일자 + 고객ID + 상품ID`로 구성되어 있을 때, `주문일자 + 고객ID`로만 검색하는 경우
## 2.3.4 Index Skip Scan
- Oracle은 인덱스 선두 컬럼이 조건절에 없어도 인덱스를 활용하는 Index Skip Scan을 9i 버전에서 선보였다.
- 조건절에 빠진 인덱스 선두 컬럼의 Distinct Value 개수가 적고 후행 컬럼의 Distinct Value 개수가 많을 때 유용하다.
    - 고객 테이블에서 Distinct Value 개수가 가장 적은 컬럼이 `성별`이고 Distinct Value 개수가 가장 많은 컬럼이 `고객번호`이다.