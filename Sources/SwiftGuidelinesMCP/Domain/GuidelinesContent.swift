/// パース層の抽出結果をプレゼンテーション層へ引き渡すための中間表現。
///
/// `GuidelinesParser` を「文字列→中間値」の純粋抽出に保ち、ロケール依存の文面組み立て
/// （`GuidelinesResponseFormatter`）と分離するために設けている。両者の境界をこの enum に
/// 集約することで、整形ルールが変わってもパース層に触らず差し替え可能。
enum GuidelinesContent {
    case entireDocument(PlainText)
    case section(name: SectionName, lookup: SectionLookupResult)
}
