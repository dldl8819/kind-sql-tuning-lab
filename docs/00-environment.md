# 실습 환경

## 데이터베이스
- Oracle Database XE 21c
- Service Name: XEPDB1
- Character Set: UTF-8 (기본)

## 접속 도구
- SQL*Plus (Oracle 기본 CLI)
- SQL Developer (선택)

## 운영체제
- Windows 11 (로컬)
  - Git Bash / PowerShell 사용 가능

## 실습 계정
- 관리자 계정: SYSTEM
- 실습 계정: TUNING

## 기본 전제
- 모든 SQL 스크립트는 XEPDB1 기준으로 작성됨
- 테이블스페이스는 USERS 사용
- 실습 계정에는 QUOTA가 100MB로 설정되어 있음

## 주의 사항
- Oracle XE는 메모리/CPU 제한이 있음
- 실행계획 비용(COST)은 환경에 따라 달라질 수 있음
