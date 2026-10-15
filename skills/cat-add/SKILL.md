---
name: cat-add
description: 지금 이 Claude Code 세션을 고양이팀 데스크톱 앱(고양이팀.app)에 고양이로 추가한다. "고양이 추가해줘", "이 세션 고양이로 만들어줘", "이 폴더 고양이 만들어줘", "고양이팀에 추가", "add a cat for this session", "make this session a cat" 같은 요청에 쓴다.
---

# 이 세션을 고양이로 추가

고양이팀 앱에 "이 작업 폴더를 맡는 고양이를 만들어 달라"는 요청 파일을 넣는다. 앱이 몇 초 안에 읽고 고양이를 만든다.

1. 폴더: 이 세션의 작업 폴더 (환경 정보의 Primary working directory, 모르면 `pwd`). 절대 경로 그대로 쓴다.
2. 이름·직군: 사용자가 말했으면 쓰고, 아니면 빈 문자열 `""` 로 둔다 (앱이 폴더 이름을 붙인다). 지어내지 않는다.
3. 아래 명령을 한 번에 실행한다. `FOLDER`, `NAME`, `ROLE` 세 값만 바꾼다. JSON 은 직접 쓰지 말고 이 명령이 만들게 둔다 (따옴표·역슬래시가 있는 경로도 안전하다. python3, jq 는 없을 수 있어 쓰지 않는다).

```bash
FOLDER="$(pwd)"; NAME=""; ROLE=""
INBOX="$HOME/Library/Application Support/고양이팀/inbox"
mkdir -p "$INBOX" && TMP="$INBOX/.req-$$-$RANDOM" &&
/usr/bin/osascript -l JavaScript -e 'function run(a){return JSON.stringify({folder:a[0],name:a[1],role:a[2]})}' "$FOLDER" "$NAME" "$ROLE" > "$TMP" &&
mv "$TMP" "$INBOX/$(date +%Y%m%d-%H%M%S)-$RANDOM.json" &&
open -g -b local.catteam
```

4. 사용자에게 짧게 알린다: 몇 초 안에 고양이가 나타나 "새로 왔어요!" 하고 인사한다 (이미 그 폴더 고양이가 있으면 "이미 있어요!"). 이름·품종은 메뉴 막대 고양이 아이콘 → 팀원 관리에서 바꿀 수 있다.

`open` 이 실패하면 고양이팀.app 이 설치되지 않은 것이다. 요청 파일은 남아 있다가 앱을 켜면 처리된다고 알려 준다.
