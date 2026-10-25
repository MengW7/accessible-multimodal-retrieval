import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';

import 'model/storage_failure.dart';

Uint8List float32Blob(EmbeddingVector vector) {
  if (!vector.normalized) {
    throw const StorageException(
      StorageFailure(
        kind: StorageFailureKind.notNormalized,
        message: 'Stored vectors must already be L2-normalized.',
      ),
    );
  }
  if (vector.dim != vector.values.length) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.dimensionMismatch,
        message: 'dim ${vector.dim} does not match ${vector.values.length} values.',
      ),
    );
  }
  final Uint8List bytes = Uint8List(vector.dim * 4);
  final ByteData view = ByteData.sublistView(bytes);
  for (var index = 0; index < vector.dim; index++) {
    final double value = vector.values[index];
    if (!value.isFinite) {
      throw StorageException(
        StorageFailure(
          kind: StorageFailureKind.notNormalized,
          message: 'Vector component $index is not finite.',
        ),
      );
    }
    view.setFloat32(index * 4, value, Endian.little);
  }
  return bytes;
}

Float32List floatsFromBlob(Uint8List bytes, int dim) {
  if (bytes.length != dim * 4) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.dimensionMismatch,
        message: 'Blob length ${bytes.length} is not $dim float32 values.',
      ),
    );
  }
  final ByteData view = ByteData.sublistView(bytes);
  final Float32List values = Float32List(dim);
  for (var index = 0; index < dim; index++) {
    values[index] = view.getFloat32(index * 4, Endian.little);
  }
  return values;
}

double dot(List<double> left, List<double> right) {
  var sum = 0.0;
  for (var index = 0; index < left.length; index++) {
    sum += left[index] * right[index];
  }
  return sum;
}
