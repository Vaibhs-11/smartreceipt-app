enum ExportSource {
  collection,
  search,
}

class ExportContext {
  const ExportContext.collection({
    this.title,
    this.dateRangeLabel,
  }) : source = ExportSource.collection;

  const ExportContext.search({
    this.title,
    this.dateRangeLabel,
  }) : source = ExportSource.search;

  final ExportSource source;
  final String? title;
  final String? dateRangeLabel;
}
