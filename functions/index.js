const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { OpenAI } = require('openai');
const fs = require('fs');
const path = require('path');
const os = require('os');

admin.initializeApp();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

exports.transcribeAudio = functions.runWith({ secrets: ["OPENAI_API_KEY"] }).https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
  }

  const audioBytes = data.audio;
  if (!audioBytes) {
    throw new functions.https.HttpsError('invalid-argument', 'The function must be called with audio data.');
  }

  const tempFilePath = path.join(os.tmpdir(), 'speech.m4a');
  fs.writeFileSync(tempFilePath, Buffer.from(audioBytes));

  try {
    const transcription = await openai.audio.transcriptions.create({
      file: fs.createReadStream(tempFilePath),
      model: "whisper-1",
    });

    // Clean up temp file
    fs.unlinkSync(tempFilePath);

    return { text: transcription.text };
  } catch (error) {
    console.error('Transcription error:', error);
    throw new functions.https.HttpsError('internal', 'Transcription failed: ' + error.message);
  }
});
