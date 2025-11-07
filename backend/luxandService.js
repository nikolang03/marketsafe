// luxandService.js - Handles all Luxand API calls
import fetch from 'node-fetch';
import dotenv from 'dotenv';
import { Buffer } from 'buffer';
import FormData from 'form-data';

// Load environment variables (in case this module is imported before dotenv.config() in app.js)
dotenv.config();

const LUXAND_BASE = 'https://api.luxand.cloud';
// Luxand API endpoints based on Live API docs:
// - Recognize People in a Photo (might be for enrollment/search)
// - Verify Person in a Photo (1:1 verification)
// - Compare Facial Similarity (compare two photos)
// - Detect Liveness (liveness detection)
const API_KEY = process.env.LUXAND_API_KEY;

if (!API_KEY) {
  throw new Error('Missing LUXAND_API_KEY in environment variables. Make sure .env file exists in the backend folder with LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1');
}

// Luxand API authentication - try multiple formats
// Format 1: Bearer token (standard)
const headersBearer = {
  'Authorization': `Bearer ${API_KEY}`,
  'Content-Type': 'application/json'
};

// Format 2: Token header (some APIs use this)
const headersToken = {
  'token': API_KEY,
  'Content-Type': 'application/json'
};

// Format 3: X-API-Key header (common alternative)
const headersApiKey = {
  'X-API-Key': API_KEY,
  'Content-Type': 'application/json'
};

// Default to token header (since Bearer doesn't work for this API key)
const headers = headersToken;

// Log which format we're using (for debugging)
console.log(`🔑 API Key loaded: ${API_KEY.substring(0, 10)}...${API_KEY.substring(API_KEY.length - 4)}`);
console.log(`🔑 Using auth format: Authorization: Bearer token`);

/**
 * Enroll a face photo to Luxand using Person API
 * @param {string} base64Image - Base64 encoded image
 * @param {string} name - Subject name (usually email)
 * @returns {Promise<Object>} - { uuid, name, faces }
 */
export async function enrollPhoto(base64Image, name) {
  // Use Person API endpoint: POST /v2/person (Enroll a Person)
  // According to Luxand docs:
  // - Endpoint: https://api.luxand.cloud/v2/person
  // - Auth: token: <api_key> (not Bearer!)
  // - Format: multipart/form-data
  // - Parameters: name (text), photos (file)
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/v2/person`);
  console.log(`📤 Using 'token' header for authentication`);
  console.log(`📤 Base64 image length: ${base64Image.length}`);
  console.log(`📤 Base64 preview: ${base64Image.substring(0, 30)}...`);
  
  // Validate base64
  if (!base64Image || base64Image.length < 100) {
    throw new Error('Invalid base64 image: too short or empty');
  }
  
  // Convert base64 to buffer for file upload
  const imageBuffer = Buffer.from(base64Image, 'base64');
  console.log(`📤 Image buffer size: ${imageBuffer.length} bytes`);
  
  // Create multipart/form-data using form-data library (proper format)
  // Parameters: name (text), photos (file) - note: "photos" not "photo"!
  const formData = new FormData();
  
  // Add 'name' field (text)
  formData.append('name', name);
  
  // Add 'photos' field (file) - this is the key parameter name from docs!
  formData.append('photos', imageBuffer, {
    filename: 'face.jpg',
    contentType: 'image/jpeg'
  });
  
  console.log(`📤 Sending multipart/form-data with 'name' and 'photos' fields`);
  console.log(`📤 Form data size: ${formData.getLengthSync()} bytes`);
  
  // Headers: token (not Bearer!) + form-data will add Content-Type with boundary
  const headers = {
    'token': API_KEY, // This is the correct format per Luxand docs!
    ...formData.getHeaders() // This adds Content-Type with proper boundary
  };
  
  console.log(`📤 Content-Type: ${headers['Content-Type']}`);
  
  // Make request to /v2/person endpoint
  const res = await fetch(`${LUXAND_BASE}/v2/person`, {
    method: 'POST',
    headers: headers,
    body: formData
  });
  
  console.log(`📥 Luxand response status: ${res.status} ${res.statusText}`);
  
  const responseText = await res.text();
  console.log(`📥 Raw Luxand response (first 500 chars):`, responseText.substring(0, 500));
  
  if (!res.ok && res.status !== 201) {
    console.error(`❌ Luxand enroll error response:`, responseText.substring(0, 500));
    throw new Error(`Luxand enroll error (${res.status}): ${responseText.substring(0, 200)}`);
  }

  // Try to parse JSON, but handle non-JSON responses
  let responseData;
  try {
    // Fix unescaped quotes in response (Luxand API bug)
    let cleanedResponse = responseText;
    // Replace unescaped quotes in message values: "message": "text "word" text" -> "message": "text \"word\" text"
    cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
      return `"message": "${p1}\\"${p2}\\"${p3}"`;
    });
    
    responseData = JSON.parse(cleanedResponse);
  } catch (parseError) {
    console.error(`❌ Failed to parse JSON response:`, parseError.message);
    console.error(`❌ Response text:`, responseText);
    
    // If it's HTML or plain text, it might be an error page
    if (responseText.includes('<!DOCTYPE') || responseText.includes('<html')) {
      throw new Error(`Luxand returned HTML instead of JSON. Response: ${responseText.substring(0, 200)}`);
    }
    
    // Try to extract message even if JSON is malformed
    const messageMatch = responseText.match(/"message":\s*"([^"]+)"/);
    if (messageMatch) {
      throw new Error(`Luxand error: ${messageMatch[1]}`);
    }
    
    // Try to extract any useful info from the response
    throw new Error(`Invalid JSON response from Luxand: ${responseText.substring(0, 200)}`);
  }
  
  console.log(`✅ Luxand enroll success (status ${res.status}):`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

/**
 * Compare two face photos
 * @param {string} base64A - First photo (base64)
 * @param {string} base64B - Second photo (base64) or stored photo ID
 * @returns {Promise<Object>} - { match, similarity, confidence }
 */
export async function comparePhotos(base64A, base64B) {
  const res = await fetch(`${LUXAND_BASE}/compare`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      photo1: base64A,
      photo2: base64B
    })
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Luxand compare error (${res.status}): ${errorText}`);
  }

  return await res.json();
}

/**
 * Verify a person in a photo (1:1 verification using person UUID)
 * @param {string} personUuid - Luxand person UUID
 * @param {string} base64Image - Base64 encoded image to verify
 * @returns {Promise<Object>} - { similarity, match, verified }
 */
export async function verifyPersonPhoto(personUuid, base64Image) {
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/v2/person/${personUuid}/verify`);
  console.log(`📤 Using 'token' header for authentication`);
  
  // Convert base64 to buffer
  const imageBuffer = Buffer.from(base64Image, 'base64');
  
  // Use multipart/form-data format
  const formData = new FormData();
  formData.append('photo', imageBuffer, {
    filename: 'verify.jpg',
    contentType: 'image/jpeg'
  });
  
  const headers = {
    'token': API_KEY,
    ...formData.getHeaders()
  };
  
  const res = await fetch(`${LUXAND_BASE}/v2/person/${personUuid}/verify`, {
    method: 'POST',
    headers: headers,
    body: formData
  });

  console.log(`📥 Luxand verify response status: ${res.status} ${res.statusText}`);
  
  const responseText = await res.text();
  console.log(`📥 Raw Luxand verify response (first 500 chars):`, responseText.substring(0, 500));

  if (!res.ok) {
    console.error(`❌ Luxand verify error response:`, responseText.substring(0, 500));
    throw new Error(`Luxand verify error (${res.status}): ${responseText.substring(0, 200)}`);
  }

  // Handle JSON parsing with unescaped quotes (Luxand API bug)
  let responseData;
  try {
    let cleanedResponse = responseText;
    cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
      return `"message": "${p1}\\"${p2}\\"${p3}"`;
    });
    responseData = JSON.parse(cleanedResponse);
  } catch (parseError) {
    console.error(`❌ Failed to parse verify response:`, parseError.message);
    throw new Error(`Invalid JSON response from Luxand verify: ${responseText.substring(0, 200)}`);
  }
  
  console.log(`✅ Luxand verify success:`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

/**
 * Check liveness of a photo
 * @param {string} base64Image - Base64 encoded image
 * @returns {Promise<Object>} - { liveness: 'real'|'fake', score: number }
 */
export async function livenessCheck(base64Image) {
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/liveness`);
  
  const res = await fetch(`${LUXAND_BASE}/liveness`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      photo: base64Image
    })
  });

  console.log(`📥 Luxand liveness response status: ${res.status} ${res.statusText}`);

  if (!res.ok) {
    const errorText = await res.text();
    console.error(`❌ Luxand liveness error response:`, errorText.substring(0, 500));
    throw new Error(`Luxand liveness error (${res.status}): ${errorText.substring(0, 200)}`);
  }

  const responseData = await res.json();
  console.log(`✅ Luxand liveness success:`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

/**
 * Search for a face among enrolled subjects (Recognize People in a Photo)
 * @param {string} base64Image - Base64 encoded image
 * @returns {Promise<Object>} - { candidates: [...] }
 */
export async function searchPhoto(base64Image) {
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/photo/search`);
  console.log(`📤 Using 'token' header for authentication`);
  
  // Convert base64 to buffer
  const imageBuffer = Buffer.from(base64Image, 'base64');
  
  // Use multipart/form-data format (like enrollment)
  const formData = new FormData();
  formData.append('photo', imageBuffer, {
    filename: 'search.jpg',
    contentType: 'image/jpeg'
  });
  
  const headers = {
    'token': API_KEY,
    ...formData.getHeaders()
  };
  
  const res = await fetch(`${LUXAND_BASE}/photo/search`, {
    method: 'POST',
    headers: headers,
    body: formData
  });

  console.log(`📥 Luxand search response status: ${res.status} ${res.statusText}`);
  
  const responseText = await res.text();
  console.log(`📥 Raw Luxand search response (first 500 chars):`, responseText.substring(0, 500));

  if (!res.ok) {
    console.error(`❌ Luxand search error response:`, responseText.substring(0, 500));
    throw new Error(`Luxand search error (${res.status}): ${responseText.substring(0, 200)}`);
  }

  // Handle JSON parsing with unescaped quotes (Luxand API bug)
  let responseData;
  try {
    let cleanedResponse = responseText;
    cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
      return `"message": "${p1}\\"${p2}\\"${p3}"`;
    });
    responseData = JSON.parse(cleanedResponse);
  } catch (parseError) {
    console.error(`❌ Failed to parse search response:`, parseError.message);
    throw new Error(`Invalid JSON response from Luxand search: ${responseText.substring(0, 200)}`);
  }
  
  console.log(`✅ Luxand search success:`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

