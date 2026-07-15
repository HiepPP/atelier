Sản phẩm nên là macOS development console viết bằng Swift, không phải bản sao VS Code.

| Lớp | Vai trò | Công nghệ |
|---|---|---|
| App shell | Điều phối project và trạng thái | SwiftUI |
| Code viewer | Đọc file, xem diff | AppKit, TextKit 2 |
| File events | Phát hiện thay đổi | FSEvents |
| Git | Status, diff, branch | Git CLI |
| Sessions | Giữ agent và server | tmux |
| Terminal | Tương tác trực tiếp | Ghostty |
| Search | Quick open, tìm file | ripgrep |
| Storage | Project registry, UI state | JSON trước, SQLite sau |

## Product Definition

Tên mô tả:

> Swift-native agent development console for macOS.

Người dùng không trực tiếp viết phần lớn code. Claude Code và Codex đảm nhiệm việc đó.

App giải quyết bốn câu hỏi:

1. Project nào đang cần chú ý?
2. Agent nào đang chạy?
3. File nào vừa thay đổi?
4. Diff nào cần review?

App dùng công cụ sẵn có. Nó chỉ cung cấp lớp điều phối mỏng.

## Product Principles

- Một project active trên UI.
- Mỗi project có tmux session riêng.
- Tmux tiếp tục chạy khi app đóng.
- Chỉ project active có FSEvents watcher.
- Git là nguồn sự thật cho changes.
- Changes là màn hình mặc định.
- File browser là công cụ phụ.
- Terminal nằm ngoài app.
- Không chạy LSP hoặc extension host.
- Không đoán trạng thái agent từ terminal text.

## Main Workflow

```text
Cmd + K
-> chọn project
-> render snapshot đã cache
-> cập nhật file, diff và branch
-> kiểm tra tmux session
-> refresh Git trong background
```

Mở terminal:

```text
Cmd + J
-> mở Ghostty
-> attach tmux session của project
```

Khi agent sửa file:

```text
FSEvents nhận thay đổi
-> debounce
-> kiểm tra file đang xem
-> chạy git status
-> cập nhật Changes
-> tải lại diff đang mở
```

## Main UI

### Projects

- Danh sách project đã đăng ký.
- Branch hiện tại.
- Tmux session sống hay tắt.
- Có thay đổi Git hay không.
- Dấu hiệu project cần chú ý.

### Files And Changes

- Changes là tab mặc định.
- Phân biệt staged, unstaged và untracked.
- Files dùng lazy loading.
- Không scan toàn repository khi chuyển project.

### Code And Diff

- Unified diff mặc định.
- Read-only file viewer.
- Monospaced text.
- Không cần syntax highlighting trong MVP.
- Hỗ trợ file renamed, deleted, binary và large file.

### Status Bar

- Claude session.
- Codex session.
- Test process.
- Dev server.
- Branch.
- Git working tree state.

## Swift Architecture

### SwiftUI Shell

SwiftUI quản lý:

- Navigation.
- Project switcher.
- Split view.
- Toolbar.
- Status bar.
- Settings.

AppKit dùng tại nơi SwiftUI chưa đủ tốt:

- Text rendering.
- Large file scrolling.
- Keyboard handling.
- Diff selection.

### Project State

Mỗi project lưu:

```text
Project identity
Repository path
Tmux session name
Last selected file
Last selected panel
Cached Git status
Cached branch
Recent UI state
```

JSON đủ cho MVP. SQLite chỉ cần khi thêm lịch sử hoặc event timeline.

Nếu app được sandbox, repository path cần security-scoped bookmark.

### Git Integration

Chạy Git bằng `Process` và argument array. Không ghép shell command string.

```text
git status --porcelain=v2 -z
git diff --no-color --no-ext-diff
git diff --cached --no-color --no-ext-diff
git branch --show-current
```

Mỗi request cần hỗ trợ cancellation. Kết quả cũ không được ghi đè project mới.

### File Watching

- Tạo watcher khi project thành active.
- Hủy watcher cũ khi chuyển project.
- Debounce nhiều event gần nhau.
- FSEvents chỉ gây invalidation.
- Không xem event path là Git truth.

### Tmux Integration

App chỉ cần:

- Kiểm tra session tồn tại.
- Liệt kê pane và foreground process.
- Tạo session khi người dùng yêu cầu.
- Yêu cầu Ghostty attach session.
- Không parse toàn bộ terminal screen.

Trạng thái MVP nên đơn giản:

```text
offline
alive
active-recently
unknown
```

Trạng thái `needs-input` cần hook hoặc event adapter từ agent.

## MVP

### P0 - Chứng minh Core Loop

- Project registry.
- `Cmd + K` project switcher.
- Git changed files.
- Unified diff viewer.
- Branch display.
- Tmux session detection.
- Ghostty attach action.
- FSEvents auto-refresh.
- Cached project switching.

### P1 - Mở Rộng Quan Sát

- Lazy file tree.
- Read-only file viewer.
- Quick open bằng ripgrep.
- Basic syntax highlighting.
- Test và dev server status.
- External "Open in..." action.

### P2 - Agent Awareness

- Claude Code hooks.
- Codex event adapter.
- Needs-input status.
- Completion notifications.
- Agent activity timeline.
- Review checkpoints.

## Out Of Scope

- LSP.
- Autocomplete.
- Inline editing.
- Refactor engine.
- Debugger.
- Extension marketplace.
- Embedded terminal.
- Notebook.
- AI chat UI.
- Remote development.
- Custom Git implementation.
- Custom terminal emulator.

## Performance Targets

| Metric | Target |
|---|---:|
| Cached project switch | Dưới 100 ms p95 |
| UI blocked by Git | 0 ms |
| Active filesystem watchers | 1 project |
| Idle CPU | Gần 0% |
| Idle app memory budget | Dưới 200 MB |
| Tmux survival after app exit | 100% |

Git refresh có thể chậm trên repository lớn. UI không được chờ nó hoàn thành.

## Main Risks

| Risk | Impact | Cách giới hạn |
|---|---|---|
| Ghostty không hỗ trợ switch ổn định | Terminal flow bị vỡ | Dùng explicit attach action |
| Agent status không đáng tin | Badge gây hiểu nhầm | Chỉ báo trạng thái đã xác minh |
| Git repository lớn | Refresh chậm | Cache, cancellation, debounce |
| Large file | Viewer dùng nhiều RAM | File-size limit, incremental loading |
| Scope creep thành IDE | Mất lợi thế nhẹ | Giữ danh sách out-of-scope |
| Nhiều agent sửa cùng repo | Diff thay đổi liên tục | Refresh theo working tree truth |

## Product Thesis

App thành công khi người dùng có thể:

```text
Giữ 5-10 project đang chạy
-> chỉ dùng một native app để quan sát
-> chuyển project tức thì
-> review thay đổi
-> quay lại đúng tmux session
-> không cần giữ nhiều VS Code window
```

Giá trị không nằm ở việc render code tốt hơn VS Code. Giá trị nằm ở việc giảm chi phí điều phối agent.

## Recap

- Yêu cầu: tổng hợp idea IDE custom viết lại bằng Swift.
- Kết quả: sản phẩm được định nghĩa thành native agent development console.
- Kiến trúc: SwiftUI, AppKit, Git CLI, FSEvents, tmux, Ghostty và JSON.
- Phạm vi: Changes-first MVP, không xây lại editor ecosystem.
- Hàm ý: xây lớp điều phối mỏng, tận dụng toàn bộ công cụ hiện có.

## What Next

Bước tiếp theo nên chuyển concept này thành product spec có acceptance criteria.

```text
prompt: Chuyển bản tổng hợp Swift-native agent development console thành product spec v0.1. Định nghĩa user stories, screen states, Swift component boundaries, state transitions, failure handling, MVP acceptance criteria và kế hoạch triển khai theo milestone. Chưa viết code.
```