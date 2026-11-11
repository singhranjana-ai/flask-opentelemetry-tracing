
from flask import Flask
import time

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor

app = Flask(__name__)

# EC2 server name
resource = Resource.create({
    "service.name": "node_server"
})

# OpenTelemetry configuration
provider = TracerProvider(resource=resource)
trace.set_tracer_provider(provider)

# Send traces to monitoring server
exporter = OTLPSpanExporter(
    endpoint="http://MONITORING_PRIVATE_IP:4318/v1/traces"
)

provider.add_span_processor(
    BatchSpanProcessor(exporter)
)

# Automatically trace Flask requests
FlaskInstrumentor().instrument_app(app)


@app.route("/")
def home():
    return "Welcome to Flask OpenTelemetry Tracing Lab!"


@app.route("/hello")
def hello():
    return "Hello Students!"


@app.route("/slow")
def slow():
    time.sleep(3)
    return "Slow request completed!"


@app.route("/error")
def error():
    return 1 / 0


app.run(host="0.0.0.0", port=5000)
