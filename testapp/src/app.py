# ~/testapp/src/app.py
from flask import Flask
import socket

app = Flask(__name__)

@app.route("/")
def home():
    return f"Hello! My name Is LEE JONG HA!! {socket.gethostname()}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
