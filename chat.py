from openai import OpenAI
from dotenv import load_dotenv
import os
import json

# Load API key
load_dotenv()
client = OpenAI()

# File paths
audio_file_path = "/Users/aarushdubey/Documents/RecordingTest/capture.wav"
conversation_file = "/Users/aarushdubey/Documents/RecordingTest/conversation.json"

# Transcribe the audio file
with open(audio_file_path, "rb") as audio_file:
    transcription = client.audio.transcriptions.create(
        file=audio_file,
        model="whisper-1",
        response_format="json"
    )

transcribed_text = transcription.text
# print(f"🎤 Added audio transcript: '{transcribed_text}'")
# Load existing conversation or create new one
try:
    with open(conversation_file, 'r') as f:
        messages = json.load(f)
    print(f"📚 Loaded conversation with {len(messages)-1} previous messages")
except FileNotFoundError:
    messages = [{"role": "system", "content": "You are an assistant"}]
    print("🆕 Starting new conversation")

# Add the new audio transcript
if transcribed_text.strip():  # Only add if there's actual content
    messages.append({"role": "user", "content": f"Here is the latest audio transcript:\n\n{transcribed_text}"})
    

# Interactive chat loop
while True:
    query = input("Q: ")
    if query.lower() in {"exit", "quit"}:
        # Save conversation before exiting
        with open(conversation_file, 'w') as f:
            json.dump(messages, f, indent=2)
        print(f"💾 Conversation saved with {len(messages)} messages")
        break
    
    messages.append({"role": "user", "content": query})
    
    response = client.chat.completions.create(
        model="gpt-4.1-mini",
        messages=messages
    )
    
    answer = response.choices[0].message.content
    messages.append({"role": "assistant", "content": answer})
    print(f"A: {answer}\n")

# Optional: Print final message count (remove if you don't want this)
print(f"Final conversation length: {len(messages)} messages")