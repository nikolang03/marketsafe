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
 * Compare two face photos using Luxand's Compare Facial Similarity API
 * @param {string} base64A - First photo (base64)
 * @param {string} base64B - Second photo (base64)
 * @returns {Promise<Object>} - { similarity, match, confidence }
 */
export async function comparePhotos(base64A, base64B) {
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/photo/compare`);
  console.log(`📤 Using 'token' header for authentication`);
  
  // Convert base64 to buffer
  const imageBufferA = Buffer.from(base64A, 'base64');
  const imageBufferB = Buffer.from(base64B, 'base64');
  
  // Use multipart/form-data format
  const formData = new FormData();
  formData.append('photo1', imageBufferA, {
    filename: 'photo1.jpg',
    contentType: 'image/jpeg'
  });
  formData.append('photo2', imageBufferB, {
    filename: 'photo2.jpg',
    contentType: 'image/jpeg'
  });
  
  const headers = {
    'token': API_KEY,
    ...formData.getHeaders()
  };
  
  const res = await fetch(`${LUXAND_BASE}/photo/compare`, {
    method: 'POST',
    headers: headers,
    body: formData
  });

  console.log(`📥 Luxand compare response status: ${res.status} ${res.statusText}`);
  
  const responseText = await res.text();
  console.log(`📥 Raw Luxand compare response (first 500 chars):`, responseText.substring(0, 500));

  if (!res.ok) {
    console.error(`❌ Luxand compare error response:`, responseText.substring(0, 500));
    throw new Error(`Luxand compare error (${res.status}): ${responseText.substring(0, 200)}`);
  }

  // Handle JSON parsing
  let responseData;
  try {
    let cleanedResponse = responseText;
    cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
      return `"message": "${p1}\\"${p2}\\"${p3}"`;
    });
    responseData = JSON.parse(cleanedResponse);
  } catch (parseError) {
    console.error(`❌ Failed to parse compare response:`, parseError.message);
    throw new Error(`Invalid JSON response from Luxand compare: ${responseText.substring(0, 200)}`);
  }
  
  console.log(`✅ Luxand compare success:`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

/**
 * Verify a person in a photo (1:1 verification using person UUID)
 * @param {string} personUuid - Luxand person UUID
 * @param {string} base64Image - Base64 encoded image to verify
 * @returns {Promise<Object>} - { similarity, match, verified }
 */
export async function verifyPersonPhoto(personUuid, base64Image) {
  // According to Luxand API docs: POST https://api.luxand.cloud/photo/verify/{uuid}
  // This is the correct endpoint format for "Verify Person in a Photo"
  const endpoints = [
    `${LUXAND_BASE}/photo/verify/${personUuid}`, // Correct endpoint from Luxand docs
    `${LUXAND_BASE}/person/${personUuid}/verify`, // Fallback (old format)
    `${LUXAND_BASE}/v2/person/${personUuid}/verify`, // Fallback (v2 format)
  ];
  
  console.log(`📤 Calling Luxand: POST ${endpoints[0]} (will try alternatives if needed)`);
  console.log(`📤 Using 'token' header for authentication`);
  
  // Convert base64 to buffer once (reuse for all endpoint attempts)
  const imageBuffer = Buffer.from(base64Image, 'base64');
  
  // Try each endpoint format
  for (const endpoint of endpoints) {
    let timeoutId;
    try {
      console.log(`📤 Trying endpoint: ${endpoint}`);
      
      // Add timeout to prevent hanging (2 seconds per endpoint attempt - very short since this endpoint may not be available)
      const controller = new AbortController();
      timeoutId = setTimeout(() => controller.abort(), 2000);
      
      // Create new FormData for each attempt (prevents memory leak warning)
      const formData = new FormData();
      formData.append('photo', imageBuffer, {
        filename: 'verify.jpg',
        contentType: 'image/jpeg'
      });
      
      const headers = {
        'token': API_KEY,
        ...formData.getHeaders()
      };
      
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: headers,
        body: formData,
        signal: controller.signal
      });
      
      clearTimeout(timeoutId);

      console.log(`📥 Luxand verify response status: ${res.status} ${res.statusText}`);
      
      const responseText = await res.text();
      console.log(`📥 Raw Luxand verify response (first 500 chars):`, responseText.substring(0, 500));

      if (!res.ok) {
        // If 404 or 405, this endpoint format is not available - try next or give up
        if ((res.status === 404 || res.status === 405) && endpoint !== endpoints[endpoints.length - 1]) {
          console.warn(`⚠️ Endpoint ${endpoint} returned ${res.status}, trying next format...`);
          continue;
        }
        // If 405 on last endpoint, this feature is not available in this plan
        if (res.status === 405) {
          throw new Error(`1:1 verify endpoint not available in your Luxand plan (405 Method Not Allowed)`);
        }
        console.error(`❌ Luxand verify error response:`, responseText.substring(0, 500));
        throw new Error(`Luxand verify error (${res.status}): ${responseText.substring(0, 200)}`);
      }
      
      // Success - parse and return
      let responseData;
      try {
        // Try parsing directly first (most responses are valid JSON)
        responseData = JSON.parse(responseText);
      } catch (parseError) {
        // If parsing fails, try to fix unescaped quotes (Luxand API bug in some responses)
        try {
          let cleanedResponse = responseText;
          cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
            return `"message": "${p1}\\"${p2}\\"${p3}"`;
          });
          responseData = JSON.parse(cleanedResponse);
        } catch (secondParseError) {
          console.error(`❌ Failed to parse verify response:`, parseError.message);
          console.error(`❌ Response text:`, responseText.substring(0, 500));
          throw new Error(`Invalid JSON response from Luxand verify: ${responseText.substring(0, 200)}`);
        }
      }
      
      console.log(`✅ Luxand verify success:`, JSON.stringify(responseData).substring(0, 200));
      return responseData;
    } catch (fetchError) {
      // Clear timeout if it was set
      if (timeoutId) clearTimeout(timeoutId);
      
      // If this is the last endpoint, throw the error
      if (endpoint === endpoints[endpoints.length - 1]) {
        // Provide clearer error message for aborted/timeout cases
        if (fetchError.name === 'AbortError' || fetchError.message.includes('aborted')) {
          throw new Error('1:1 verify endpoint timed out or not available in this Luxand plan');
        }
        throw fetchError;
      }
      // Otherwise, try next endpoint
      if (fetchError.name === 'AbortError' || fetchError.message.includes('aborted')) {
        console.warn(`⚠️ Endpoint ${endpoint} timed out (not available), trying next format...`);
      } else {
        console.warn(`⚠️ Endpoint ${endpoint} failed: ${fetchError.message}, trying next...`);
      }
      continue;
    }
  }
  
  // If we get here, all endpoints failed
  throw new Error('All verify endpoint formats failed');
}

/**
 * Check liveness of a photo
 * @param {string} base64Image - Base64 encoded image
 * @returns {Promise<Object>} - { liveness: 'real'|'fake', score: number }
 */
export async function livenessCheck(base64Image) {
  // Note: Luxand liveness endpoint may not be available in all API plans
  // This is optional and failures are handled gracefully
  // According to Luxand docs: POST https://api.luxand.cloud/photo/liveness/v2
  console.log(`📤 Calling Luxand: POST ${LUXAND_BASE}/photo/liveness/v2`);
  
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout
    
    // Convert base64 to buffer for multipart/form-data
    const imageBuffer = Buffer.from(base64Image, 'base64');
    
    // Use multipart/form-data format (as shown in Luxand docs)
    const formData = new FormData();
    formData.append('photo', imageBuffer, {
      filename: 'liveness.jpg',
      contentType: 'image/jpeg'
    });
    
    const headers = {
      'token': API_KEY,
      ...formData.getHeaders()
    };
    
    const res = await fetch(`${LUXAND_BASE}/photo/liveness/v2`, {
      method: 'POST',
      headers: headers,
      body: formData,
      signal: controller.signal
    });

    clearTimeout(timeoutId);
    console.log(`📥 Luxand liveness response status: ${res.status} ${res.statusText}`);

    if (!res.ok) {
      const errorText = await res.text();
      console.error(`❌ Luxand liveness error response:`, errorText.substring(0, 500));
      
      // If 404, the endpoint is not available (might not be in the plan)
      if (res.status === 404) {
        throw new Error('LIVENESS_ENDPOINT_NOT_AVAILABLE');
      }
      
      throw new Error(`Luxand liveness error (${res.status}): ${errorText.substring(0, 200)}`);
    }

    // Handle JSON parsing
    const responseText = await res.text();
    let responseData;
    try {
      // Fix unescaped quotes in response (Luxand API bug)
      let cleanedResponse = responseText;
      cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
        return `"message": "${p1}\\"${p2}\\"${p3}"`;
      });
      responseData = JSON.parse(cleanedResponse);
    } catch (parseError) {
      console.error(`❌ Failed to parse liveness response:`, parseError.message);
      throw new Error(`Invalid JSON response from Luxand liveness: ${responseText.substring(0, 200)}`);
    }
    
    console.log(`✅ Luxand liveness success:`, JSON.stringify(responseData).substring(0, 200));
    return responseData;
  } catch (error) {
    // If endpoint doesn't exist (404) or times out, throw a specific error
    if (error.name === 'AbortError' || error.message.includes('aborted')) {
      console.warn('⚠️ Liveness check timed out or was aborted');
      throw new Error('LIVENESS_ENDPOINT_NOT_AVAILABLE');
    }
    if (error.message.includes('404') || 
        error.message.includes('Not Found') || 
        error.message === 'LIVENESS_ENDPOINT_NOT_AVAILABLE') {
      throw new Error('LIVENESS_ENDPOINT_NOT_AVAILABLE');
    }
    throw error;
  }
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

/**
 * Delete a person from Luxand by UUID
 * @param {string} personUuid - Luxand person UUID
 * @returns {Promise<Object>} - { success: boolean, message: string }
 */
export async function deletePerson(personUuid) {
  console.log(`📤 Calling Luxand: DELETE ${LUXAND_BASE}/person/${personUuid}`);
  console.log(`📤 Using 'token' header for authentication`);
  
  const headers = {
    'token': API_KEY,
  };
  
  const res = await fetch(`${LUXAND_BASE}/person/${personUuid}`, {
    method: 'DELETE',
    headers: headers
  });

  console.log(`📥 Luxand delete response status: ${res.status} ${res.statusText}`);
  
  const responseText = await res.text();
  console.log(`📥 Raw Luxand delete response (first 500 chars):`, responseText.substring(0, 500));

  if (!res.ok && res.status !== 204) {
    console.error(`❌ Luxand delete error response:`, responseText.substring(0, 500));
    throw new Error(`Luxand delete error (${res.status}): ${responseText.substring(0, 200)}`);
  }

  // Handle JSON parsing (some APIs return empty body on success)
  let responseData = { success: true, message: 'Person deleted successfully' };
  if (responseText && responseText.trim().length > 0) {
    try {
      let cleanedResponse = responseText;
      cleanedResponse = cleanedResponse.replace(/"message":\s*"([^"]*)"([^"]*)"([^"]*)"/g, (match, p1, p2, p3) => {
        return `"message": "${p1}\\"${p2}\\"${p3}"`;
      });
      responseData = JSON.parse(cleanedResponse);
    } catch (parseError) {
      console.warn(`⚠️ Failed to parse delete response, assuming success: ${parseError.message}`);
    }
  }
  
  console.log(`✅ Luxand delete success:`, JSON.stringify(responseData).substring(0, 200));
  return responseData;
}

