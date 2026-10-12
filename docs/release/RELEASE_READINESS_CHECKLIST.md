# RIVAL iOS Release Readiness Checklist

배포·심사에서 실제 수행한 항목과 남은 실계정·출시 확인 항목을 분리해 관리한다.

- **대상:** RIVAL 1.2(6) 심사 제출본 · 마케팅 버전 `1.2`, 빌드 번호 `6`
- **문서 기준일:** 2026-10-12 · 제출 상태의 마지막 확인은 2026-10-11
- **설정 기준:** [RIVAL.xcodeproj/project.pbxproj](../../ios-pixel-boxing/RIVAL.xcodeproj/project.pbxproj), [project.yml](../../ios-pixel-boxing/project.yml), [PixelBoxingIOS/Info.plist](../../ios-pixel-boxing/PixelBoxingIOS/Info.plist)
- **상태:** 사용자가 아카이브·시뮬레이터 캡처·업로드·심사 제출을 추가로 요청해 실행했다. `1.2(6)` Release 아카이브를 업로드하고 앱·Story 상품·Total Wins 순위표 3개 항목을 2026-10-11 06:31 GMT+9에 함께 제출했다. 당시 확인한 상태는 `Waiting for Review`이며 승인·스토어 출시 완료가 아니다. 앱 가격은 변경하지 않았고 수동 출시를 유지했다. 실기기 설치와 Production/Sandbox 계정 결제는 수행하지 않았다. 이번 문서 정리에서는 새 배포 조회·빌드·제출을 하지 않았다.

## 현재 준비 상태

- [x] 실제 앱 Debug/Release와 프로젝트 명세를 `1.2` / `6`으로 맞춤.
- [x] 실제 Release 설정의 버전·빌드 번호, iPhone·iPad 지원 `1,2`, `DEBUG` 조건 없음 확인.
- [x] Archive 스킴이 Release를 사용함을 확인. 임시 Story 해금은 Debug에만 남아 있고 Release에서는 비활성화됨.
- [x] 배포용 스토리는 압박형 → 견제형 → 카운터형 → 강타형 → RIVAL 순서로 앞선 상대들을 이겨야 다음 도전을 해금함. 상대전의 최종 승리만 진행에 반영하고, 인트로 다시보기는 관람 후, 승리 후 컷씬·엔딩은 해당 상대 승리 후 해금하는 코드 경로 확인. 구매만으로 전부 해금하지 않음.
- [x] [PixelBoxingIOS/PrivacyInfo.xcprivacy](../../ios-pixel-boxing/PixelBoxingIOS/PrivacyInfo.xcprivacy)에 앱 내부 UserDefaults 저장 사유 `CA92.1` 선언. 실제 앱 Resources에 1회 등록 및 plist 문법 확인.
- [x] Connect에 iOS `1.2` 초안을 생성하고 수동 출시 설정 유지.
- [x] 영어·한국어·일본어 홍보 문구, 설명, 업데이트 내용과 공통 심사 메모를 저장하고 새로고침 후 유지 확인. 원문은 [AppStoreMetadata/1.2.json](../../ios-pixel-boxing/AppStoreMetadata/1.2.json)에 보관.
- [x] 스토리 상품의 현재 저장된 한국 기준 가격 `KRW 4,400`, 자동 환산 가격 미국 `USD 2.99`·일본 `JPY 500` 확인. 요청한 4천원대 가격으로 이미 설정되어 있어 중복 가격 일정은 만들지 않음. 지원 175개 국가·지역 전체 판매 설정 유지.
- [x] 순위표 코드의 인증·대기 점수 제출·일반 RIVAL 승리 집계·갱신·상위 항목 밖 내 기록 표시 경로 확인. 스토리 승리는 순위표 집계에서 제외됨. 관련 에디터 오류 없음. 실제 계정의 제출 성공을 확인한 것은 아님.
- [x] 실제 프로젝트의 GameKit 연결·Game Center 엔타이틀먼트, 최종 `1.2(6)` 아카이브의 서명 권한·앱 ID와 strict codesign 검증 확인.
- [x] Connect `1.2`의 Game Center 활성화와 기본 순위표 ID `com.acertainromance401.pixelboxing.totalWins` 일치 확인. Classic / Integer / Best Score / High to Low / Hidden No 설정이며 점수 범위 제한 없음. 앱 버전과 함께 제출해 현재 심사 대기 중임.
- [x] 가격·활성 구매 버튼·Restore Purchases가 보이는 최신 영문 구매 화면을 상품의 필수 심사 스크린샷으로 등록하고 재접속 확인. 선택 사항인 1024×1024 홍보 이미지는 등록하지 않음.
- [x] 영어·한국어·일본어의 iPhone 6.9인치 및 iPad 13인치 실제 화면 각 5장, 총 30장을 `1.2`에 연결. 전투 → 체육관 → 메인 메뉴 → 스토리 진행 → 구매 화면 순서. 기존 승인 이미지는 Asset Library에 보존하고 이번 버전의 이전 연결만 제거함.
- [x] Release 캡처 테스트 총 6개 통과, 실패 0개와 첨부 30장의 이름·언어별 개수 확인. Apple 로컬 StoreKitTest에서 구매 후 첫 상대 도전 가능·두 번째 상대 잠금·미해금 다시보기 부재 확인. 실제 Production 결제 검증은 아님.
- [x] 캡처 중 발견한 상대 목록 중앙 터치 실패를 [PixelBoxingIOS/StoryViews.swift](../../ios-pixel-boxing/PixelBoxingIOS/StoryViews.swift)의 전체 사각형 hit area로 수정하고 동일 캡처로 확인. 먼저 업로드한 빌드 `5` 대신 수정된 `6`을 심사에 선택함.
- [ ] 실제 Sandbox/TestFlight 상품 조회·구매·취소·보류·복원·권한 취소 확인. Debug 임시 해금으로 통과를 판단하지 않음.
- [ ] 기존 유료 구매자의 권한·진행 기록 유지와 신규 무료 구매자의 스토리 잠금을 실제 계정에서 확인.
- [x] 첫 Story 상품과 첫 Game Center 순위표를 `1.2(6)` 앱 버전과 함께 심사 제출. 기존 단독 제출 차단은 해소됐으며 세 항목 모두 `Waiting for Review`를 확인함. 심사 승인은 아직 아님.
- [ ] 실계정 Game Center 인증 → 일반 RIVAL 승리 → 순위표의 내 기록 갱신 → 앱 재실행·오프라인 후 재접속 제출을 실제 환경에서 확인. 현재 Debug 스토리 체험은 통계 저장·점수 전송을 막으므로 해당 체험 상태로 검증하지 않음. Release에는 이 제한이 없음.
- [x] 2026-10-12 공개 지원·개인정보 문서의 로컬 원본에 현재 조작, 구매·복원, 로컬 습관 저장, Apple 거래·랭킹 정보와 네트워크 조건을 반영. 1.2 기능은 출시 예정으로 표시하고 문서 구조·내용 검사 통과.
- [ ] GitHub Pages 배포 후 실제 공개 지원·개인정보 페이지 확인 및 Connect 개인정보 응답과 최종 대조.
- [x] 최종 Release 아카이브와 앱 Info.plist 양쪽의 `1.2(6)`, iPhone·iPad 지원, 서명, 아이콘과 개인정보 매니페스트 포함 확인. Story JSON 11개를 포함하며 테스트용 `.storekit` 파일은 앱에 없음.
- [x] 작업용 iPhone·iPad 기기 2개 삭제·목록 대조 확인. 이번에 생성한 전용 DerivedData, 실패 캡처·중복 원본, 캡처 xcresult와 미사용 빌드 `5`만 정리함. 기존 iOS 26.1 런타임·다른 기기·기존 빌드 산출물은 보존함. 디스크 여유 공간은 `21,773,596 KiB` → `25,987,236 KiB`로 약 `4.02 GiB` 증가. 최종 `6` 아카이브·dSYMs·이미지 30장·성공 요약과 첨부 목록 JSON은 보존함.
- [ ] 무료 전환 일정과 기존 유료 구매자 경계를 확정. 현재 원본 빌드 번호만으로 기존 유료 권한을 판단하므로, 가격을 먼저 무료로 바꾸거나 구버전이 함께 배포되는 시차에는 신규 무료 사용자가 유료 구매자로 분류될 위험이 있음. 필요 시 검증된 원본 구매일 경계를 반영한 뒤 전환.

## 심사 제출 기록

- 제출 ID: `f6f6275f-bf74-4531-acca-f309d091960f`
- [App Store Connect 제출 상세](https://appstoreconnect.apple.com/apps/6799909429/distribution/reviewsubmissions/details/f6f6275f-bf74-4531-acca-f309d091960f)
- 제출 내역·캡처 범위: [AppStoreMetadata/1.2-submission.json](../../ios-pixel-boxing/AppStoreMetadata/1.2-submission.json)
- 보존 아카이브(로컬 전용, Git 제외): `ios-pixel-boxing/build/RIVAL-1.2-6-20261011-review.xcarchive`. 공개 저장소에는 아카이브 다운로드 링크를 제공하지 않는다.
- 보존 구매 화면: [AppStoreScreenshots/1.2/iphone-6.9/en-US/02-story-purchase.png](../../ios-pixel-boxing/AppStoreScreenshots/1.2/iphone-6.9/en-US/02-story-purchase.png), [AppStoreScreenshots/1.2/ipad-13/en-US/02-story-purchase.png](../../ios-pixel-boxing/AppStoreScreenshots/1.2/ipad-13/en-US/02-story-purchase.png)

## 1. 기존 전체 자동 점검 (미실행)

아래는 기존 전체 점검 절차다. 이번 작업은 서명된 Release archive/export와 범위를 제한한 Release UI 캡처를 실행했으며, 이 전체 스크립트나 XcodeGen 재생성은 실행하지 않았다. 직접 등록한 리소스가 있으므로 XcodeGen 재생성은 별도 확인 후 수행한다.

필요할 때 실행할 명령:

```bash
cd ios-pixel-boxing
chmod +x scripts/pre_release_check.sh
./scripts/pre_release_check.sh --device-id <UDID>
```

자동 점검 통과 기준:

- XcodeGen 재생성 성공
- Generic iOS 무서명 `build-for-testing` 성공
- Generic iOS 무서명 `Release build` 성공
- (옵션) `--device-id`를 지정한 실기기 `test-without-building` 성공

스크립트의 generic iOS 단계는 `CODE_SIGNING_ALLOWED=NO` 컴파일이다. 실기기 테스트는
기기에서 실행 가능한 서명·설치 조건과 테스트 산출물이 별도로 갖춰져 있어야 한다.
무서명 빌드 통과 또는 실기기 테스트 생략을 실기기 실행·배포 검증 완료로 기록하지 않는다.

로그:

- `/tmp/rival_pre_release_YYYYMMDD_HHMMSS.log`

## 2. 수동 점검 (필수)

- 실기기 가로 고정, Safe Area, 노치 영역 가독성 확인
- 대기실/설정/랭킹/체육관 모달 열림-닫힘 플로우 확인
- 실전 2~3라운드 플레이로 더킹/가드/백스텝/위빙·훅 연계/카운터 체감 확인
- 현재 기본 사거리·공통 추가 리치 14·선수 최소 간격 34와 3개 스타일의 판정·모션 일치 확인
- 위빙 비용 9·동작 0.36초·연계 시작 0.23초의 조작감과 피격·메뉴 전환 시 예약 취소 확인
- KO 연출 이후 결과 패널과 다음 라운드 버튼 동작 확인
- 한국어/영어/일본어 전환 시 주요 텍스트 반영 확인
- 동작 줄이기(Reduce Motion) 켠 상태에서 과도한 카메라/트레일 억제 확인
- 사운드/햅틱 OFF 시 실제 무음/무진동 확인
- 20~30분 연속 플레이에서 프레임 드롭, 입력 누락, 비정상 메시지 반복 여부 확인
- 연속 플레이 전/후 메모리 증가 추세를 비교해 급격한 누수 징후가 없는지 확인

## 3. App Store Connect 직전 확인

- 마케팅 버전 `1.2`/최종 빌드 번호 `6` 확인: 설정뿐 아니라 최종 아카이브·앱 Info.plist의 실제 값도 확인
- 이미 업로드한 빌드 번호인지 App Store Connect에서 확인하고 재업로드에는 사용 가능한 번호 선택
- 현재 소스·커밋과 최종 아카이브의 대응 기록을 남기고 과거 같은 버전 산출물과 구분
- 앱 아이콘/런치 이미지 최신 반영 확인
- Game Center leaderboard ID 일치 여부 확인
- 개인정보 처리방침/연령 등급/스크린샷/가격 정보 최신화 확인
- 제출용 PDF·플레이 영상·스크린샷이 현행 Markdown·실제 빌드와 일치하는지 확인

### 무료 전환과 스토리 상품 준비

- 무료 RIVAL 모드를 스토리보다 위에 배치하며, RIVAL·체육관·일반 복장 보상은 스토리 구매 없이 이용한다.
- 상품 ID: `com.acertainromance401.pixelboxing.story`. 비소모성 1회 구매로 전체 스토리 이용권을 제공하며 구독이 아니다.
- 구매 혜택: 상대 5명의 순차 대결, 경기 저장·이어하기, 진행에 따른 컷씬과 다시 보기. 스토리 전용 시작 복장 `퍼스트 벨 / First Bell`은 구매 즉시 해금하며 클리어가 필요하지 않다. 매트 블랙 쇼츠, 진홍색 사이드 패널·글러브, 흰색 허리밴드·스티치의 외형 전용 복장이다.
- 클리어 보상은 구매만으로 지급하지 않는다. 해당 상대의 스토리 대결을 직접 클리어해야 상대별 복장·외형을 해금하며, 챔피언십 우승으로 파이널 챔피언 복장과 벨트를 해금한다. 시작 복장과 얻은 클리어 보상은 무료 RIVAL에서도 착용한다.
- 기존 유료 구매자 경계는 검증된 Production 앱 거래의 원본 빌드 `4` 이하이다. iOS의 `originalAppVersion`은 마케팅 버전이 아니라 빌드 번호다. 제출본은 `1.2(6)`이며, 이를 유료 앱 가격으로 먼저 출시하면 신규 유료 구매자에게 Story가 잠길 수 있으므로 자동 출시를 설정하지 않았다. 반대로 무료 가격 적용 중 구버전을 신규 취득하면 원본 빌드 기준으로 기존 권한을 받을 수 있다. 가격·버전 배포 시차와 원본 구매일 조건은 실제 전환 전 확정해야 한다.
- Connect 상품: `Story Mode`, Apple ID `6821357632`, 상태 `Waiting for Review`. 한국어·영어·일본어 상품 설명, 최신 심사 메모와 구매 화면 이미지 저장·재접속 확인 후 앱과 함께 제출했다.
- 현재 상품 가격은 한국 기준 `KRW 4,400`이며 미국 `USD 2.99`·일본 `JPY 500`이 저장된 가격표에 표시된다. 다른 지역은 Apple 자동 환산이며 지원 175개 국가·지역 전체 판매 설정을 유지한다. 캡처 가격은 로컬 US storefront `$2.99`이며 한국 storefront 실결제 캡처가 아니다. 앱 자체 가격은 한국 `KRW 3,300`·미국 `USD 1.99`·일본 `JPY 300`으로 유지했고 판매 개시 일정은 변경하지 않았다.
- 첫 인앱결제와 첫 Game Center 순위표를 앱 `1.2(6)`과 같은 제출에 포함했다. 최초 단독 제출 차단은 해소됐고 세 항목 모두 심사 대기다. 승인 전에는 상품·순위표의 Production 활성화 또는 App Store 출시 완료로 기록하지 않는다.
- 스토리 잠금과 기존 구매자 권한 유지가 반영된 업데이트 및 상품 심사 준비 없이 현행 앱 가격을 먼저 무료로 바꾸지 않는다. 무료 전환 시점과 유료 구매자 경계를 함께 확정한다.

## 4. 아직 완료되지 않은 범위

- Apple의 심사 승인과 실제 스토어 출시, 무료 가격 전환은 아직 완료되지 않았다.
- 2026-10-12 공개 App Store 확인 당시 유료 `1.1`이었다. [홍보 영상](../../ios-pixel-boxing/PromotionVideos/README.md)의 스토리 장면은 출시 예정 1.2 미리보기이며 광고 요청의 심사 상태와 앱 심사·출시 상태를 구분한다.
- 로컬 StoreKitTest 캡처는 실계정 Sandbox/Production 구매·복원·권한 취소 또는 기존 유료 구매자 전환 검증을 대체하지 않는다.
- 실제 계정 Game Center 점수 제출·재접속 갱신과 장시간 실기기 플레이는 수행하지 않았다. 지원·개인정보 로컬 원본은 갱신했지만 Pages 배포 성공·실제 공개 페이지 반영과 Connect 응답 대조는 별도 확인 사항이다.

## 5. 공개 지원 문서 원본

2026-10-12 [지원 원본](../../pixel-boxing/support/index.html)과
[개인정보 원본](../../pixel-boxing/privacy/index.html)을 갱신했다. 예전 방향 버튼 안내와
앱 전체 오프라인·Game Center 정보는 점수 제출만 사용한다는 설명을 교정하고,
출시 전 Story 구매·복원과 지원 이메일 처리도 구분했다. 기존 Pages workflow는
`main`의 `pixel-boxing/**` 변경을 배포하지만 푸시만으로 배포 완료를 보장하지 않는다.
아래는 핵심 안내 문안이며 실제 페이지에는 1.2 출시 전 표시가 함께 있다.

```text
Do I need an internet connection?
RIVAL matches, the Gym, and the AI run on your device. Story purchases, Restore Purchases, and the optional Game Center leaderboard require a network connection. No separate app account is required.

How do I unlock Story Mode?
Tap Story on the main menu. The optional, one-time purchase permanently unlocks the campaign and the First Bell starter outfit. Other Story outfits and the championship belt require the corresponding victories. There is no subscription.

How do I restore Story access?
Open the Story purchase screen and choose Restore Purchases using the Apple account associated with the purchase. Eligible existing paid-app customers keep Story access without paying again. Restoring access does not restore deleted local campaign progress.

Controls
Use the movement arrows to change position. Tap JAB or CROSS to punch. Hold GUARD or the left/right DUCK controls for defense, tap BACKSTEP to evade backward, and use the left/right WEAVE controls for lateral evasion. The Gym provides the current combination controls.
```
