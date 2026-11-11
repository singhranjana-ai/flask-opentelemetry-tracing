
#!/bin/bash

# Install Python
sudo dnf install python3 python3-pip -y

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install required packages
pip install -r requirements.txt

# Start Flask application
python app.py
