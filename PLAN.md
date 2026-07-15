# Atelier - Kế Hoạch MVP

Swift-native lightweight IDE cho macOS. Mục tiêu: ổn định, nhẹ, vừa đủ để explore file, chạy CLI trong terminal đa tab, và làm việc với Git cơ bản.

Đây là bản thu hẹp từ `IDEA.md`. Khác biệt chính: terminal chuyển từ ngoài app (tmux + Ghostty) sang nhúng trong app (multi-tab). Bỏ phần điều phối đa agent khỏi MVP.

## Mục Tiêu

- Một app native, khởi động nhanh, idle gần 0% CPU.
- Đủ để dùng hàng ngày thay cho việc mở nhiều cửa sổ lẻ.
- Không cạnh tranh VS Code về tính năng editor. Không LSP, không autocomplete.

App trả lời ba nhu cầu:

1. File nào có trong project và nội dung ra sao.
2. Chạy lệnh CLI ngay trong app, nhiều tab song song.
3. File nào thay đổi, diff thế nào, commit cơ bản.

## Phạm Vi MVP

Bốn khối tính năng.

| Khối | Nội dung | Trạng thái |
|---|---|---|
| File explorer | Cây thư mục lazy, xem file read-only | Core |
| Terminal | Nhúng, đa tab, chạy shell tại cwd của workspace | Core |
| Git diff | Unified diff read-only cho file thay đổi | Core |
| Git changes + basic | Staged/unstaged/untracked, stage, commit, branch | Core |

Một workspace mở tại một thời điểm (một folder gốc). Chuyển workspace = mở folder khác.

## Kiến Trúc

| Lớp | Vai trò | Công nghệ |
|---|---|---|
| App shell | Navigation, split view, toolbar, state | SwiftUI |
| File explorer | Cây thư mục, lazy load | NSOutlineView (AppKit) bọc trong SwiftUI |
| File viewer | Đọc file, monospaced, read-only | TextKit 2 (AppKit) |
| Terminal | PTY, đa tab | SwiftTerm (cần spike xác nhận) |
| Git | status, diff, branch, commit | Git CLI qua `Process` |
| Diff render | Hiển thị unified diff | TextKit 2, dùng output `git diff` |
| Storage | Workspace gần nhất, UI state | JSON |

Nguyên tắc giữ nguyên từ IDEA:

- Git là nguồn sự thật cho changes.
- Changes là màn hình mặc định.
- Chạy Git bằng `Process` + argument array, không ghép shell string.
- Mỗi Git request hỗ trợ cancellation. UI không bao giờ chờ Git.

## Thành Phần

### File Explorer

- Cây thư mục dựa trên `NSOutlineView` để cuộn mượt và lazy expand.
- Chỉ đọc thư mục con khi node được mở. Không scan toàn repo lúc mở workspace.
- Bỏ qua `.git` và các folder nặng theo danh sách cấu hình (ví dụ `node_modules`).
- Click file mở viewer read-only. Không sửa inline trong MVP.
- File lớn: giới hạn kích thước, load tăng dần, cảnh báo nếu vượt ngưỡng.

### Terminal

- Nhúng bằng SwiftTerm, mỗi tab là một PTY chạy shell mặc định của user (`$SHELL`).
- cwd của tab mới = folder gốc workspace.
- Đa tab: thêm, đóng, đổi tab. Tab giữ session khi chuyển sang panel khác.
- Terminal sống độc lập với các panel Git/file.
- Không parse nội dung terminal để đoán trạng thái. Terminal chỉ để chạy lệnh.

Spike bắt buộc trước khi cam kết: dựng LocalProcessTerminalView của SwiftTerm, chạy shell, verify resize, copy/paste, và màu cơ bản.

### Git Diff

- Unified diff là mặc định.
- Lấy diff trực tiếp từ `git diff` và `git diff --cached`, render read-only.
- Hỗ trợ file renamed, deleted, binary, và file lớn (giới hạn dòng hiển thị).
- Không cần syntax highlighting trong MVP.

### Git Changes Và Basic

- Danh sách thay đổi từ `git status --porcelain=v2 -z`.
- Phân biệt staged, unstaged, untracked.
- Thao tác cơ bản: stage, unstage, discard (có xác nhận), commit với message.
- Hiển thị branch hiện tại. Đổi branch cơ bản.
- FSEvents watch workspace để tự refresh changes. Debounce nhiều event gần nhau.
- FSEvents chỉ gây invalidation, không phải Git truth. Sau event luôn chạy lại `git status`.

Lệnh Git dùng:

```text
git status --porcelain=v2 -z
git diff --no-color --no-ext-diff
git diff --cached --no-color --no-ext-diff
git add / git restore --staged
git branch --show-current
git checkout <branch>
git commit -m <message>
```

## State Và Storage

Lưu tối thiểu, JSON là đủ:

```text
Workspace path (security-scoped bookmark nếu sandbox)
Last selected file
Last active panel
Open terminal tabs (số lượng, cwd)
Cached branch
```

Cache Git status trong bộ nhớ để render tức thì khi quay lại panel. Kết quả Git cũ không được ghi đè state mới (guard theo workspace path + request id).

## State Transitions

### Workspace Lifecycle

Một workspace tại một thời điểm. Chuyển workspace phải dọn sạch state cũ trước khi mở mới.

```text
        [empty]
           |
           | user chọn folder (NSOpenPanel)
           v
        [opening] --- lỗi/bookmark stale ---> [empty]
           |
           | resolve bookmark OK, start FSEvents
           v
        [active] <--- refresh xong --- [refreshing]
           |  ^                             ^
           |  | FSEvents/refresh thủ công   |
           |  +-----------------------------+
           |
           | user mở folder khác  |  đóng app
           v                      v
        [closing]              [terminated]
           |
           | dừng watcher, stop security scope, save JSON
           v
        [opening]  (folder mới)  hoặc  [empty]
```

Bất biến:

- Chỉ `[active]` mới có FSEvents watcher sống.
- Vào `[closing]` phải hủy watcher cũ và cancel mọi Git request đang chạy trước khi vào `[opening]`.
- Kết quả Git trả về sau khi rời workspace bị loại (guard theo workspace id).

### Git Refresh Sau FSEvents

FSEvents chỉ kích hoạt invalidation. Git luôn là nguồn sự thật cuối.

```text
FSEvents callback (nhiều path)
      |
      v
  debounce (gộp event trong cửa sổ ~200 ms)
      |
      v
  bỏ qua nếu chỉ .git/ nội bộ hoặc path đã ignore
      |
      v
  cancel Git request cũ còn treo
      |
      v
  chạy: git status --porcelain=v2 -z   (nền, có cancellation)
      |
      +--> workspace đã đổi?  --yes--> loại kết quả, dừng
      |
      no
      v
  cập nhật Changes list (staged/unstaged/untracked)
      |
      v
  diff đang mở?  --yes--> đánh dấu "có thay đổi, bấm reload"
      |                    (KHÔNG tự thay nội dung đang đọc)
      no
      v
  idle
```

Bất biến:

- UI không bao giờ chờ Git đồng bộ. Mọi cập nhật đến qua callback nền.
- Diff đang review không bị auto-thay; chỉ hiện cờ reload.
- Debounce + cancel ngăn bão event trên repo lớn.

## Milestones

| Mốc | Nội dung | Xong khi |
|---|---|---|
| M0 | App skeleton, mở folder, nhớ folder gần nhất | Mở lại app tự load workspace cũ |
| M1 | File explorer lazy + viewer read-only | Duyệt cây, mở file, cuộn mượt |
| M2 | Terminal nhúng đa tab | Chạy CLI, mở nhiều tab, resize đúng |
| M3 | Git changes list + unified diff | Thấy staged/unstaged/untracked, xem diff |
| M4 | Git basic: stage, unstage, commit, branch | Commit thành công từ app |
| M5 | Stability pass, đạt performance target | Không blocking UI, idle gần 0% |

Thứ tự này chứng minh core loop sớm: explore + run CLI + review changes.

## Out Of Scope

- LSP, autocomplete, inline editing, refactor engine, debugger.
- Extension marketplace, notebook, AI chat UI.
- Điều phối đa agent, tmux, Ghostty attach (đẩy về giai đoạn sau).
- Remote development.
- Custom Git implementation, custom terminal emulator.
- Multi-project switcher với watcher song song (MVP chỉ một workspace).

## Rủi Ro

| Rủi ro | Impact | Cách giới hạn |
|---|---|---|
| SwiftTerm không đủ ổn định | Terminal flow vỡ | Spike sớm ở M2, fallback đánh giá lại lib |
| Git repo lớn refresh chậm | Lag khi status | Cache, cancellation, debounce, chạy nền |
| File lớn ngốn RAM | Viewer nặng | Giới hạn kích thước, load tăng dần |
| FSEvents bão event | CPU tăng | Debounce, coalesce, chỉ watch workspace active |
| Scope creep thành IDE đầy đủ | Mất lợi thế nhẹ | Giữ danh sách out-of-scope |
| Diff nhảy khi file đổi lúc đang đọc | Review UX vỡ | Pin snapshot, báo "có thay đổi, bấm reload" |

## Acceptance Criteria

- Mở workspace và render explorer dưới mốc mục tiêu, không blocking UI.
- Terminal chạy lệnh thật, đa tab, sống khi chuyển panel.
- Changes hiển thị đúng trạng thái Git sau khi sửa file ngoài app.
- Commit từ app phản ánh đúng trên `git log`.
- Idle CPU gần 0%, memory dưới ngưỡng ngân sách.

## Performance Targets

| Metric | Target |
|---|---:|
| Mở file trong viewer | Dưới 100 ms p95 (file thường) |
| UI bị Git chặn | 0 ms |
| FSEvents watcher active | 1 workspace |
| Idle CPU | Gần 0% |
| Idle memory | Dưới 200 MB |
