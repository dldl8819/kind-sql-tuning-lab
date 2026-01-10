# 2.2 인덱스 기본 사용법
- 인덱스를 Range Scan 하는 방법
    - 인덱스를 Range Scan할 수 없게 되는 이유를 알아보자
## 2.2.1 인덱스를 사용한다는 것
- Index Range Scan
    - 리프 블록 일부만 스캔 
    - 인덱스 컬럼을 가공하지 않아야 인덱스를 정상적으로 사용할 수 있다.
        - 리프 블록에서 스캔 시작점을 찾아 거기서부터 스캔하다가 중간에 멈추는 것이 가능
- Index Full Scan
    - 일부가 아닌 전체를 스캔
    - 인덱스 컬럼을 가공해도 인덱스를 사용할 수는 있지만, 스캔 시작점을 찾을 수 없고 멈출 수도 없어서 리프 블록 전체를 스캔해야 한다.    
## 2.2.2 인덱스를 Range Scan 할 수 없는 이유
- 인덱스 컬럼을 가공했을 때 Index Range Scan할 수 없는 이유는 `인덱스 스캔 시작점을 찾을 수 없기 때문`이다.
    - Range가 범위를 의미하는데 일정 범위를 스캔하려면 시작점과 끝지점이 있어야 한다.
        - 2007년 1월에 태어난 사람을 찾는 예
            ```SQL
            where 생년월일 between '20070101' and '20070131'
            ```
    - 스캔 시작점과 끝지점을 알 수 없는 예        
        - 년도와 상관없이 5월에 태어난 사람을 찾는 예
            ```SQL
            where substr(생년월일, 5, 2) = '05'
            ```
        - LIKE로 중간 값을 검색할 때
            ```SQL
            where 업체명 like '%대한%'
            ```
- OR Expansion
    - SQL 옵티마이저는 OR 조건을 분해하고 각 조건에 대해 독립적인 Index Range Scan을 수행할 수 있다.
        ```SQL
        where (전화번호 = :tel_no OR 고객명 = :cust_nm)
        ```
        - use_concat 힌트로 강제할 수 있다.
            - 내부적으로 UNION ALL 형태로 변환
                ```SQL
                select  *
                from    고객
                where   고객명 = :cust_nm
                union all
                select  *
                from    고객
                where   전화번호 = :tel_no
                and     (고객명 <> :cust_nm or 고객명 is null)
                ```
- IN 조건절
    - 수직적 탐색으로 전화번호가 '01012345678'이거나 '01098765432'인 어느 한 지점을 바로 찾는 것은 불가능
        ```SQL
            where 전화번호 in ( :tel_no1, :tel_no2)
        ```
    - IN 조건도 OR 조건을 표현하는 다른 방식일 뿐이어서 UNION ALL 방식으로 각 브랜치 별로 인덱스 스캔 시작점을 찾을 수 있다.
        - Range Scan 가능
            ```SQL
            select  *
            from    고객
            where   전화번호 = :tel_no1
            union all
            select  *
            from    고객
            where   전화번호 = :tel_no2
            ```
        - SQL 옵티마이저가 IN-LIST Iterator 방식을 사용
            - IN-List 개수만큼 Index Range Scan을 반복
## 2.2.3 더 중요한 인덱스 사용 조건
- 인덱스 선두 컬럼이 가공되지 않은 상태로 조건절에 있어야 한다.
    - 인덱스를 `소속팀 + 사원명 + 연령` 순으로 구성했을 때 아래 조건절에 대해 Range Scan이 가능할까?
        ```SQL
        select  사원번호, 소속팀, 연령, 입사일자, 전화번호
        from    사원
        where   사원명 = '홍길동'
        ```        
    - 이름이 같은 사원이라도 소속팀이 다르면 서로 떨어지게 되어 인덱스 스캔 시작점을 찾을 수 없다.
        - 사원명은 선두 컬럼이 아니고 선두 컬럼인 소속팀이 조건절에 없음
- 인덱스 Range Scan을 한다고 해서 항상 성능이 좋은 건 아니다.
    - SQL을 개발하면서 실행 계획을 확인하지 않는 개발자가 대다수다.
    - 확인하더라도 인덱스를 타는지(Range Scan) 여부를 확인하는 수준에 그친다.
        ```
        Execution Plan
        -----------------------------------------------------------------------
        0     SELECT STATEMENT Optimizer=ALL_ROWS
        1   0   TABLE ACCESS (BY INDEX ROWID) OF '주문상품' (TABLE)
        2   1     INDEX (RANGE SCAN) OF '주문상품_N1' (INDEX)
        -----------------------------------------------------------------------
        ```
        - 인덱스를 잘 타니까 문제가 없을까?
            - 주문상품_N1 인덱스는 `주문일자 + 상품번호` 순으로 구성됐고, 이 테이블에 쌓이는 데이터량은 하루 평균 100만건일 때
                - 중간 값 검색
                ```SQL
                SELECT  *
                FROM    주문상품
                WHERE   주문일자 = :ord_dt
                AND     상품번호 LIKE '%PING%';
                ```
                - 컬럼 가공
                ```SQL
                SELECT  *
                FROM    주문상품
                WHERE   주문일자 = :ord_dt
                AND     SUBSTR(상품번호, 1, 4) = 'PING';
                ```                    
                - 두 SQL 모두 상품번호는 스캔 범위를 줄이는 데 전혀 역할을 하지 못했다.
## 2.2.4 인덱스를 이용한 소트 연산 생략
- PK가 `장비번호 + 변경일자 + 변경순번` 순으로 구성된 상태변경이력 테이블의 예
    - 장비번호와, 변경일자가 같은 레코드는 변경순번 순으로 정렬돼 있다.
        ```SQL
        SELECT  *
        FROM    상태변경이력
        WHERE   장비번호 = 'C'
        AND     변경일자 = '20180316'
        ```
        ```
        Execution Plan
        -----------------------------------------------------------------------
        0     SELECT STATEMENT Optimizer=ALL_ROWS
        1   0  TABLE ACCESS (BY INDEX ROWID) OF '상태변경이력' 
        2   1    INDEX (RANGE SCAN) OF '상태변경이력_PK' 
        ```
        - 옵티마이저는 SQL에 ORDER BY가 있어도 정렬 연산을 따로 수행하지 않는다.
            - PK 인덱스를 스캔하면서 출력한 결과집합이 어차피 변경순번 순으로 정렬되기 때문에 SORT ORDER BY 연산이 생략된다.
                ```SQL
                SELECT   *
                FROM     상태변경이력
                WHERE    장비번호 = 'C'
                AND      변경일자 = '20180316'
                ORDER BY 변경순번
                ```
                ```
                Execution Plan
                -------------------------------------------------------------
                0     SELECT STATEMENT Optimizer=ALL_ROWS
                1   0  TABLE ACCESS (BY INDEX ROWID) OF '상태변경이력' 
                2   1    INDEX (RANGE SCAN) OF '상태변경이력_PK' 
                ```
- 정렬 연산을 생략할 수 있게 인덱스가 구성돼 있지 않으면 SORT ORDER BY 연산 단계가 추가된다.
    ```
    Execution Plan
    ---------------------------------------------------------------------------
    0     SELECT STATEMENT Optimizer=ALL_ROWS
    1   0   SORT (ORDER BY)
    2   1     TABLE ACCESS (BY INDEX ROWID) OF '상태변경이력'
    3   2       INDEX (RANGE SCAN) OF '상태변경이력_PK' 
    ```
- 내림차순 정렬에서 인덱스 활용
    - 조건을 만족하는 가장 큰 값을 찾아 우측으로 수직적 탐색을 하고 좌측으로 수평적 탐색
- 오름차순 정렬에서 인덱스 활용
    - 조건을 만족하는 가장 작은 값을 찾아 좌측으로 수직적 탐색을 하고 우측으로 수평적 탐색
## 2.2.5 ORDER BY 절에서 컬럼 가공
- ORDER BY 또는 SELECT-LIST에서 컬럼을 가공하여 인덱스를 정상적으로 사용할 수 없는 경우
    ```SQL
    SELECT   *
    FROM     상태변경이력
    WHERE    장비번호 = 'C'
    ORDER BY 변경일자 || 변경순번
    ```
    - 인덱스에는 가공하지 않은 상태로 값을 저장했는데, 가공한 값 기준으로 정렬해야 할 경우 정렬 연산 생략 불가능
    ```SQL
    SELECT *
    FROM   (
        SELECT   
                 TO_CHAR(A.주문번호, 'FM000000') AS 주문번호, 
                 A.업체번호, 
                 A.주문금액
        FROM     주문 A
        WHERE    A.주문일자 = :dt
        AND      A.주문번호 > NVL(:next_ord_no, 0)
        ORDER BY 주문번호
    )
    WHERE ROWNUM <= 30
    ```
    ```
    --------------------------------------------------------------------------
    | Id | Operation                       | Name                            |
    | 0  | SELECT STATEMENT                |                                 |
    | 1  |  COUNT STOPKEY                  |                                 |
    | 2  |   VIEW                          |                                 |
    | 3  |    SORT ORDER BY STOPKEY        |                                 |
    | 4  |     TABLE ACCESS BY INDEX ROWID | 주문                             |
    | 5  |      INDEX RANGE SCAN           | 주문_PK                          |
    ```
    - ORDER BY절의 주문번호는 TO_CHAR 함수로 가공한 주문번호이기 때문에 정렬 연산 생략이 안되었다.
    ```SQL
    SELECT *
    FROM   (
        SELECT   
                 TO_CHAR(A.주문번호, 'FM000000') AS 주문번호, 
                 A.업체번호, 
                 A.주문금액
        FROM     주문 A
        WHERE    A.주문일자 = :dt
        AND      A.주문번호 > NVL(:next_ord_no, 0)
        ORDER BY A.주문번호
    )
    WHERE ROWNUM <= 30
    ```
    ```
    --------------------------------------------------------------------------
    | Id | Operation                       | Name                            |
    | 0  | SELECT STATEMENT                |                                 |
    | 1  |  COUNT STOPKEY                  |                                 |
    | 2  |   VIEW                          |                                 |
    | 4  |     TABLE ACCESS BY INDEX ROWID | 주문                             |
    | 5  |      INDEX RANGE SCAN           | 주문_PK                          |
    ```
    - ORDER BY절 주문번호에 A(주문 테이블 Alias)를 붙여주면 SORT ORDER BY 연산이 생략된다.
## 2.2.6 SELECT-LIST에서 컬럼 가공
- 인덱스를 `장비번호 + 변경일자 + 변경순번` 순으로 구성하면 변경순번 최소값, 최대값을 구할 때 정렬 연산을 따로 수행하지 않는다.
    - 인덱스 리프 블록의 왼쪽 또는 오른쪽에서 레코드 하나만 읽고 멈춘다.
    ```SQL
    SELECT MIN(변경순번), MAX(변경순번)
    FROM   상태변경이력
    WHERE  장비번호 = 'C'
    AND    변경일자 = '20180316'
    ```
    ```
    Rows Row Source Operation
    ---- ----------------------------------------------
       0 STATEMENT
       1 SORT AGGREGATE 
       1  FIRST ROW
       1   INDEX RANGE SCAN (MIN/MAX) 상태변경이력_PK
    ```
- 인덱스에는 문자열 기준으로 정렬돼 있는데 숫자값으로 바꾼 값 기준으로 최종 변경순번을 요구하는 컬럼 가공을 진행하면 정렬 연산을 생략할 수 없다.
    - 집계 함수(MIN/MAX) 안에서 컬럼을 가공하면 인덱스 정렬을 활용할 수 없다.
    ```SQL
    SELECT NVL(MAX(TO_NUMBER(변경순번)), 0)
    FROM   상태변경이력
    WHERE  장비번호 = 'C'
    AND    변경일자 = '20180316'
    ```
    ```
    Rows   Row Source Operation
    ------ ----------------------------------------------
         0 STATEMENT
         1  SORT AGGREGATE 
    131577   INDEX RANGE SCAN (MIN/MAX) 상태변경이력_PK
    ```
    - SQL을 아래와 같이 바꾸면 정렬 연산 생략이 가능하고, 애초에 변경순번 데이터타입이 숫자형이면 이렇게 튜닝할 필요도 없다.
    ```SQL
    SELECT NVL(TO_NUMBER(MAX(변경순번)), 0)
    FROM   상태변경이력
    WHERE  장비번호 = 'C'
    AND    변경일자 = '20180316'
    ```
    ```
    Rows Row Source Operation
    ---- ----------------------------------------------
       0 STATEMENT
       1 SORT AGGREGATE 
       1  FIRST ROW
       1   INDEX RANGE SCAN (MIN/MAX) 상태변경이력_PK
    ```
## 2.2.7 자동 형변환
- 오라클에서 숫자형과 문자형이 만나면 숫자형이 이긴다.    
    - 숫자형 컬럼 기준으로 문자형 컬럼을 변환한다.
        - 고객 테이블에 생년월일이 선두 컬럼인 인덱스 예
            ```SQL
            SELECT * FROM 고객
            WHERE 생년월일 = 19821225
            ```
            ```
            Execution Plan
            -------------------------------------------------------------------0     SELECT STATEMENT Optimizer=ALL_ROWS
            1   0  TABLE ACCESS (FULL) OF '고객            

            Predicate information (identified by operation_id):
            --------------------------------
            1 - filter(TO_NUMBER("생년월일")= 19821225)
            ```
            - 생년월일 컬럼을 조건절에서 가공하지도 않았는데 테이블 전체 스캔
                - 옵티마이저가 SQL을 아래와 같이 변환하여 인덱스 컬럼이 가공됐기 때문에 Range Scan 불가능
                ```SQL
                SELECT * FROM 고객
                WHERE TO_NUMBER(생년월일) = 19821225
                ```
                - 고객 테이블 생년월일 컬럼이 문자형인데 조건절 비교값을 숫자형으로 표현해서 나타난 현상
    - 연산자가 LIKE일 경우 LIKE 자체가 문자열 비교 연산자이므로 문자형 기준으로 숫자형 컬럼이 변환된다.
        ```SQL
        SELECT * FROM 고객
        WHERE 고객번호 LIKE '9410%'
        ```
        ```
        Execution Plan
        -----------------------------------------------------------------------
        0     SELECT STATEMENT Optimizer=ALL_ROWS
        1   0  TABLE ACCESS (FULL) OF '고객' (TABLE)
        -----------------------------------------------------------------------

        Predicate information (identified by operation id):
        -----------------------------------------------------------------------
        1 - filter(TO_CHAR("고객번호") LIKE '9410%')
        -----------------------------------------------------------------------
        ```
        - LIKE 조건을 옵션 조건 처리 목적으로 사용하는 경우
            - 거래 데이터 조회 시 계좌번호를 사용자가 입력할 수도 있고 안 할 수도 있는 옵션 조건
                - 사용자가 계좌번호를 입력할 경우
                ```SQL 
                SELECT * FROM 거래
                WHERE  계좌번호 = :acnt_no
                AND    거래일자 between :trd_dt1 and :trd_dt2
                ```
                - 사용자가 계좌번호를 입력하지 않을 경우
                ```SQL 
                SELECT * FROM 거래
                WHERE  거래일자 between :trd_dt1 and :trd_dt2
                ```
                - LIKE 조건으로 위 두 SQL을 처리하는 방식 
                ```SQL
                SELECT * FROM 거래
                WHERE  계좌번호 LIKE :acnt_no || '%'
                AND    거래일자 between :trd_dt1 and :trd_dt2
                ```
                - 조회할 때 사용자가 계좌번호를 입력하지 않으면 :acnt_no 변수에 NULL 값을 입력하여 모든 계좌번호가 조회되도록 할 수 있다.
                    - LIKE, BETWEEN 조건이 같이 사용되어 비효율적이다.
- 날짜형과 문자형이 만나면 날짜형이 이긴다.
    - 좌변 컬럼 기준으로 우변을 변환하여 인덱스 사용엔 문제가 없다.
        - DATE 타입인 가입날짜 컬럼이 있고 VARCHAR2 타입인 '01-JAN-2018'이 있으면 암묵적 형변환 규칙으로 좌변인 데이터 타입을 기준으로 우변을 변환한다.
            ```SQL
            WHERE 가입날짜 = '01-JAN-2018';
            ```
            ```SQL
            WHERE 가입날짜 = TO_DATE('01-JAN-2018', NLS_DATE_FORMAT)
            ```
            - 이 예제에서 가공되는 것은 인덱스 컬럼이 아니고 리터럴 값이 DATE로 변환됨
            - 인덱스 컬럼이 가공되지 않으면 인덱스 사용에는 문제가 없다.
    - NLS_DATE_FORMAT 파라미터가 다르게 설정된 환경에서 수행하면 컴파일 오류가 나거나 결과집합이 달라질 수 있어서 아래와 같이 코딩하면 안된다.
        - NLS_DATE_FORMAT : 문자열을 DATE 타입으로 변환할 때 사용하는 기본 날짜 포맷
    ```SQL
    SELECT * FROM 고객
    WHERE 가입날짜 = '01-JAN-2018';
    ```
    - 날짜 포맷을 정확히 지정해주는 코딩 습관이 필요하다
    ```SQL
    SELECT * FROM 고객
    WHERE 가입날짜 = TO_DATE('01-JAN-2018', 'DD-MON-YYYY');    
    ```
- 자동 형변환이 편리할 수도 있지만 종종 성능과 애플리케이션 품질에 악영향을 준다.
    - 숫자형 컬럼과 문자형 컬럼을 비교하면 문자형 컬럼이 숫자형으로 변환되는데, 문자형 컬럼에 숫자로 변환할 수 없는 문자열이 입력되면 쿼리 수행 도중 에러가 발생한다.
        ```SQL
        where n_col = v_col
        ```
        - 2행에 오류 : ORA-01722: 수치가 부적합합니다.
    - 결과 오류가 생기는 사례도 있다.
        ```SQL
        select 
            round(av(sal)) avg_sal,
            min(sal) min_sal,
            max(sal) max_sal,
            max(decode(job, 'PRESIDENT', NULL, sal)) max_sal2
        from emp;
        ```
        - 오라클이 decode 함수를 처리할 때 내부에서 사용하는 자동 형변환 규칙 때문에 오류 발생
            - decode(a, b, c, d)
                - 'a = b'이면 c를 반환하고, 아니면 d를 반환
                - 반환 값의 데이터 타입은 c에 의해 결정
                - c가 문자형이고 d가 숫자형이면 d는 문자형으로 변환
                - c가 null이면 varchar2로 취급
            ```SQL            
            select 
                round(av(sal)) avg_sal,
                min(sal) min_sal,
                max(sal) max_sal,
                max(decode(job, 'PRESIDENT', to_number(NULL), sal)) max_sal2
            from emp;
            ```
            - 데이터 타입을 명시적으로 일치시켜주거나 to_number(NULL) 대신 0을 써도 된다.
- 자동 형변환의 편리함에 의존하지 말고 인덱스 컬럼 기준으로 반대편 컬럼 또는 값을 정확히 형변환해주어야 한다.
- TO_CHAR, TO_DATE, TO_NUMBER 같은 형변환 함수를 생략한다고 연산횟수를 줄이는 것이 아니다.
    - 옵티마이저가 자동으로 생성한다.
- SQL 성능은 블록 I/O를 줄이는 것이 중요하다.