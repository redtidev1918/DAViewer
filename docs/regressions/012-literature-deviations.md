# REG-012 Literature 作品显示为空白详情和破图预览

## 症状

Through Closed Eyes 这类 literature 作品的 URL 形如 /{artist}/art/{slug}-{id}，
但内容是文字，没有图片 media。用户在 feed 中只看到破图占位；进入详情后正文
区域空白。

## Root cause

- DeviantArt 的 literature 作品返回 type: literature 和
  textContent.html.markup，没有图片 media；
- App 之前把“文字作品”判定绑定在 /journal/ URL 上，而 literature 使用
  /art/ URL，导致 journalHtmlProvider 不请求正文；
- feed 卡片的 media 列表为空时，只渲染通用图片占位，看起来像图片加载失败。

## Fix

- journalHtmlProvider 改为按“无缓存且是数字 deviation id + 可解析作者”或
  “已有缓存且是 journal URL / media 为空”尝试拉取正文；图片作品不会发请求；
- 详情页用“journal URL 或已取到非空正文”判定 isTextWork，从而渲染文字正文，
  不再显示 bogus original/download 区块；
- 无 media 的卡片渲染文章图标 + 标题的文字卡；已有 media 但缺 URI 的占位
  保持原状，避免测试素材和布局语义改变。

## Regression

- test/literature_deviation_test.dart：
  - media 为空的 literature 卡片渲染文字卡，不再渲染 CachedNetworkImage；
  - journalHtmlProvider 对 /art/ literature 请求 tiptap 正文；
  - 有 media 的图片作品不会触发正文请求。
- flutter analyze 无问题；全量 flutter test 共 312 个测试通过。
