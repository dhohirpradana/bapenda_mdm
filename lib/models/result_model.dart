class Result {
  final bool success;
  final String message;

  const Result({required this.success, required this.message});

  static Result ok([String msg = "Success"]) =>
      Result(success: true, message: msg);
  static Result fail([String msg = "Failed"]) =>
      Result(success: false, message: msg);
}
