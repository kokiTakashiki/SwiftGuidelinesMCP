/// ガイドラインのパース結果を、プレゼンテーション層へそのまま引き渡すための中間表現。
/// 旧名 `ExtractedBody` は「何の body なのか」が名前から読めず、HTML の `<body>` とも
/// 混同されやすかったため、ガイドライン由来のコンテンツであることを明示する名前に改めている。
enum GuidelinesContent {
    case entireDocument(PlainText)
    case section(name: SectionName, lookup: SectionLookupResult)
}
