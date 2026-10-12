# Terminal Boxing · C++20

RIVAL의 전투·라운드·저장·플레이 패턴 규칙을 처음 검증한 터미널 구현입니다. 현행 제품은 [iOS 앱](../../ios-pixel-boxing/README.md)입니다.

## 구성

- [include/game](include/game): 공개 헤더와 상태·전투·패턴 인터페이스
- [src/game](src/game): 전투 엔진, 패턴 모델, 세션, 저장과 렌더링
- [src/main.cpp](src/main.cpp): 실행 진입점
- [tests/smoke_tests.cpp](tests/smoke_tests.cpp): C++ smoke test
- [CMakeLists.txt](CMakeLists.txt): C++20 대상·선택적 FTXUI 설정

## 실행

저장소 루트에서 기존 CMake 진입점을 사용할 수 있습니다. 실행 파일은 기존처럼 `build/`에 생성합니다.

```bash
cmake -S . -B build -DGAME_USE_FTXUI=OFF
cmake --build build
./build/game_tui
```

FTXUI를 사용하는 경우에만 `-DGAME_USE_FTXUI=ON`으로 설정합니다. 고정된 의존성 커밋을 다운로드하며 네트워크가 필요합니다. macOS의 [Terminal 실행 도우미](../../scripts/open_game_terminal.sh)는 빌드된 `build/game_tui`를 엽니다.

직접 `cmake -S legacy/terminal-cpp -B build`로 구성할 수도 있습니다. 이 문서 정리에서 게임 실행·테스트는 하지 않았습니다.
