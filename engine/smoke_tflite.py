from pathlib import Path
import tensorflow as tf

root = Path(__file__).resolve().parents[1]
model_path = root / "models" / "probes" / "mobilenet_v1_1.0_224_quant.tflite"

print("TF", tf.__version__)
print("Model", model_path, "exists=", model_path.exists(), "size=", model_path.stat().st_size)

interpreter = tf.lite.Interpreter(model_path=str(model_path))
interpreter.allocate_tensors()

print("INPUTS")
for item in interpreter.get_input_details():
    print(item["name"], item["shape"], item["dtype"])

print("OUTPUTS")
for item in interpreter.get_output_details():
    print(item["name"], item["shape"], item["dtype"])

print("TFLite smoke test OK")