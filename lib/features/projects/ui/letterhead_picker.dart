import 'package:image_picker/image_picker.dart';
import '../logic/projects_cubit.dart';

Future<LetterheadImage?> pickLetterhead() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
  if (file == null) return null;
  final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'png';
  return LetterheadImage(
    bytes: await file.readAsBytes(),
    extension: ext,
    mimeType: file.mimeType ?? (ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/$ext'),
  );
}
