import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';


Future<File?> pickFile(BuildContext context, {int maxSizeInMB = 10}) async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null) {
      File file = File(result.files.single.path!);

      final bytes = await file.length();
      if (bytes > maxSizeInMB * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File size must be less than ${maxSizeInMB}MB')),
        );
        return null;
      }

      return file;
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error picking file: $e')),
    );
  }
  return null;
}
