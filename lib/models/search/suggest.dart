/// 搜索建议模型。
///
/// 移植自 PiliPlus 的 `SearchSuggestModel`。
class SearchSuggestModel {
  final List<SearchSuggestItem>? tag;

  SearchSuggestModel({this.tag});

  SearchSuggestModel.fromJson(Map<String, dynamic> json)
      : tag = (json['tag'] as List?)
            ?.map((e) => SearchSuggestItem.fromJson(e as Map<String, dynamic>))
            .toList();
}

class SearchSuggestItem {
  final String? term;
  final String? name;

  SearchSuggestItem({this.term, this.name});

  SearchSuggestItem.fromJson(Map<String, dynamic> json)
      : term = json['term'] as String?,
        name = json['name'] as String?;
}
