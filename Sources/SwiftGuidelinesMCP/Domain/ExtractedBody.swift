/// `GuidelinesParser` が抽出した本文をそのままの形で持ち、プレゼンテーション層に引き渡す中間表現。
enum ExtractedBody {
    case entireDocument(text: String)
    case section(name: SectionName, result: SectionLookupResult)
}
