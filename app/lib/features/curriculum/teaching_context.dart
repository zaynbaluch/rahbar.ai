class TeachingContext {
  const TeachingContext({this.classCode, this.className, this.subjectCode, this.subjectName});
  final String? classCode;
  final String? className;
  final String? subjectCode;
  final String? subjectName;
  bool get isEmpty => className == null && subjectName == null;
  Map<String,dynamic> toJson() => {'classCode':classCode,'className':className,'subjectCode':subjectCode,'subjectName':subjectName};
  factory TeachingContext.fromJson(Map<String,dynamic> j)=>TeachingContext(classCode:j['classCode'] as String?,className:j['className'] as String?,subjectCode:j['subjectCode'] as String?,subjectName:j['subjectName'] as String?);
}
