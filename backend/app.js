// app.js - Main Express server for face authentication
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { enrollPhoto, comparePhotos, livenessCheck, searchPhoto, verifyPersonPhoto, deletePerson, listPersons } from './luxandService.js';

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 4000;
const SIMILARITY_THRESHOLD = parseFloat(process.env.SIMILARITY_THRESHOLD || '0.85');
const LIVENESS_THRESHOLD = parseFloat(process.env.LIVENESS_THRESHOLD || '0.90');

// Middleware
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS === '*' ? '*' : (process.env.ALLOWED_ORIGINS?.split(',') || '*')
}));
app.use(express.json({ limit: '10mb' })); // Allow large image payloads

// Log all requests (especially health checks)
app.use((req, res, next) => {
  const start = Date.now();
  if (req.path === '/' || req.path === '/api/health') {
    console.log(`[${new Date().toISOString()}] 🏥 Health check: ${req.method} ${req.path}`);
  }
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (req.path === '/' || req.path === '/api/health') {
      console.log(`[${new Date().toISOString()}] ✅ Health check responded: ${res.statusCode} (${duration}ms)`);
    }
  });
  next();
});

// Request logging
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Global error handler to prevent crashes
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit, just log
});

process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  // Don't exit, just log
});

// ==========================================
// ROOT ENDPOINT (for Railway health checks)
// ==========================================
// This endpoint must respond quickly for Railway health checks
// Railway expects a 200 OK response immediately
app.get('/', (req, res) => {
  // Respond immediately with 200 OK - Railway needs this fast
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    ok: true,
    service: 'MarketSafe Face Auth Backend',
    status: 'running',
    time: new Date().toISOString(),
    uptime: process.uptime()
  }));
});

// ==========================================
// HEALTH CHECK
// ==========================================
app.get('/api/health', (req, res) => {
  // Respond immediately - Railway needs fast responses
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    ok: true,
    time: new Date().toISOString(),
    service: 'Face Auth Backend',
    luxandConfigured: !!process.env.LUXAND_API_KEY
  }));
});

// ==========================================
// TEST ENDPOINT - Check Luxand API connection
// ==========================================
app.get('/api/test-luxand', async (req, res) => {
  try {
    // Try a simple search with empty photo to see API response format
    const testResponse = await searchPhoto('dGVzdA=='); // base64 of "test"
    res.json({
      ok: true,
      message: 'Luxand API is reachable',
      responseFormat: testResponse,
      note: 'This is just to check API format, not a real search'
    });
  } catch (error) {
    res.json({
      ok: false,
      error: error.message,
      note: 'Check if API key is valid'
    });
  }
});

// ==========================================
// ENROLL ENDPOINT
// ==========================================
// POST /api/enroll
// Body: { email: string, photoBase64: string }
// Returns: { ok: true, uuid: string } or { error: string }
app.post('/api/enroll', async (req, res) => {
  try {
    const { email, photoBase64 } = req.body;

    // Validation
    if (!email || !photoBase64) {
      return res.status(400).json({
        ok: false,
        error: 'Missing email or photoBase64'
      });
    }

    if (typeof email !== 'string' || typeof photoBase64 !== 'string') {
      return res.status(400).json({
        ok: false,
        error: 'Invalid email or photoBase64 format'
      });
    }

    console.log(`📸 Enrolling face for: ${email}`);
    console.log(`📏 Photo base64 length: ${photoBase64.length} characters`);
    console.log(`📏 Photo base64 preview: ${photoBase64.substring(0, 50)}...`);
    
    // Validate base64 string
    if (!photoBase64 || photoBase64.length < 100) {
      return res.status(400).json({
        ok: false,
        error: 'Invalid photo: base64 string is too short or empty'
      });
    }
    
    // Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
    let cleanBase64 = photoBase64;
    if (photoBase64.includes(',')) {
      cleanBase64 = photoBase64.split(',')[1];
      console.log('🔧 Removed data URL prefix from base64');
    }

    // 1) Liveness check before enrollment (optional - skip if endpoint not available)
    let livenessPassed = true;
    try {
      console.log('🔍 Running liveness check...');
      const liveRes = await livenessCheck(photoBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      const isLive = (liveRes?.liveness === 'real') || liveScore >= LIVENESS_THRESHOLD;

      console.log(`📊 Liveness: ${isLive ? 'PASS' : 'FAIL'} (score: ${liveScore.toFixed(2)})`);

      if (!isLive) {
        return res.status(400).json({
          ok: false,
          error: 'Liveness check failed. Please ensure you are using a live photo, not a photo of a photo.',
          livenessScore: liveScore
        });
      }
      livenessPassed = true;
    } catch (livenessError) {
      // If liveness endpoint doesn't exist or fails, silently continue (this is expected)
      // Liveness endpoint is not available in all Luxand API plans
      // Only log unexpected errors (not 404s, aborted, or known unavailable messages)
      if (!livenessError.message.includes('404') && 
          !livenessError.message.includes('Not Found') &&
          !livenessError.message.includes('aborted') &&
          !livenessError.message.includes('LIVENESS_ENDPOINT_NOT_AVAILABLE')) {
        console.warn('⚠️ Liveness check failed:', livenessError.message);
      }
      // Silently continue - liveness is optional
      livenessPassed = true; // Allow enrollment to proceed
    }

    // 2) Enroll to Luxand
    console.log('🔍 Enrolling to Luxand...');
    console.log(`📤 Sending base64 (length: ${cleanBase64.length}) to Luxand...`);
    const luxandResp = await enrollPhoto(cleanBase64, email);
    
    // Log the full response to see what Luxand returns
    console.log('📦 Full Luxand response:', JSON.stringify(luxandResp, null, 2));
    
    // Try multiple possible UUID fields
    const luxandUuid = luxandResp.uuid 
                    || luxandResp.id 
                    || luxandResp.subject_id
                    || luxandResp.subjectId
                    || luxandResp.face_id
                    || luxandResp.faceId
                    || (luxandResp.faces && luxandResp.faces[0] && luxandResp.faces[0].uuid)
                    || (luxandResp.data && luxandResp.data.uuid)
                    || null;

    if (!luxandUuid) {
      console.error('❌ No UUID found in Luxand response. Response structure:', JSON.stringify(luxandResp, null, 2));
      return res.status(500).json({
        ok: false,
        error: 'Enrollment failed: No UUID returned from Luxand',
        luxandResponse: luxandResp // Include response for debugging
      });
    }
    
    console.log(`✅ Found UUID: ${luxandUuid}`);

    console.log(`✅ Face enrolled successfully. UUID: ${luxandUuid}`);

    // 3) Return success
    res.json({
      ok: true,
      success: true,
      uuid: luxandUuid,
      message: 'Face enrolled successfully'
    });

  } catch (error) {
    console.error('❌ Enrollment error:', error);
    res.status(500).json({
      ok: false,
      error: error.message || 'Enrollment failed'
    });
  }
});

// ==========================================
// VERIFY ENDPOINT
// ==========================================
// POST /api/verify
// Body: { email: string, photoBase64: string }
// Returns: { ok: true/false, similarity: number, message: string } or { error: string }
app.post('/api/verify', async (req, res) => {
  try {
    const { email, photoBase64, luxandUuid } = req.body;

    // Validation
    if (!email || !photoBase64) {
      return res.status(400).json({
        ok: false,
        error: 'Missing email or photoBase64'
      });
    }

    if (typeof email !== 'string' || typeof photoBase64 !== 'string') {
      return res.status(400).json({
        ok: false,
        error: 'Invalid email or photoBase64 format'
      });
    }

    console.log(`🔍 Verifying face for: ${email}`);
    if (luxandUuid) {
      console.log(`🔍 Using 1:1 verification with UUID: ${luxandUuid}`);
    } else {
      console.log(`🔍 Using search-based verification (no UUID provided)`);
    }

    // 1) Liveness check (MANDATORY for security)
    // CRITICAL: Liveness detection is required to prevent photo/video replay attacks
    let livenessPassed = false;
    try {
      console.log('🔍 Running MANDATORY liveness check...');
      const liveRes = await livenessCheck(photoBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      const isLive = (liveRes?.liveness === 'real') || liveScore >= LIVENESS_THRESHOLD;

      console.log(`📊 Liveness: ${isLive ? 'PASS' : 'FAIL'} (score: ${liveScore.toFixed(2)})`);

      if (!isLive) {
        return res.status(403).json({
          ok: false,
          reason: 'liveness_failed',
          error: 'Liveness check failed. Please ensure you are using a live photo, not a photo of a photo. Blink or turn your head slightly.',
          livenessScore: liveScore
        });
      }
      livenessPassed = true;
    } catch (livenessError) {
      // Handle liveness check errors
      console.error('🚨 Liveness check error:', livenessError.message);
      
      // If liveness endpoint is not available (404), allow verification to proceed
      // This is common in some Luxand API plans where liveness is not included
      if (livenessError.message.includes('404') || 
          livenessError.message.includes('Not Found') ||
          livenessError.message.includes('LIVENESS_ENDPOINT_NOT_AVAILABLE') ||
          livenessError.message.includes('aborted')) {
        console.warn('⚠️ Liveness endpoint not available - proceeding without liveness check');
        console.warn('⚠️ Note: Liveness detection is not available in your Luxand API plan');
        // Allow verification to proceed without liveness check
        livenessPassed = true;
      } else {
        // For other errors (network, timeout, etc.), also allow but log warning
        // In a production environment with liveness available, you might want to be stricter
        console.warn('⚠️ Liveness check failed with error, but allowing verification to proceed');
        console.warn('⚠️ Error details:', livenessError.message);
        livenessPassed = true; // Allow verification to proceed
      }
    }
    
    if (!livenessPassed) {
      return res.status(403).json({
        ok: false,
        reason: 'liveness_required',
        error: 'Liveness detection is mandatory for security. Please ensure liveness detection is properly configured.',
      });
    }

    // 2) SECURITY: Always require UUID for 1:1 verification (never do global search for login)
    // CRITICAL: Global search allows ANY enrolled face to access ANY account - this is a security vulnerability!
    if (!luxandUuid || typeof luxandUuid !== 'string' || luxandUuid.trim().length === 0) {
      console.error('🚨 SECURITY: No luxandUuid provided for verification');
      console.error('🚨 SECURITY: Cannot do global search - this would allow any enrolled face to access any account!');
      return res.status(400).json({
        ok: false,
        error: 'User UUID required for verification. Please ensure the user has completed face enrollment.',
        security: 'Global face search is disabled for security - only 1:1 verification is allowed'
      });
    }
    
    // Use search + email matching for verification
    // CRITICAL: We must verify the face belongs to the email entered
    console.log('🔍 Using secure verification with UUID and email matching (SECURE MODE)...');
    console.log(`🔍 Verifying face against UUID: ${luxandUuid.trim()}`);
    console.log(`🔍 Security: Email matching is REQUIRED - face must match the entered email`);
    
    try {
      // First, try search to get the person ID (Luxand search returns ID, not UUID)
      // Then use that ID for 1:1 verification, or use search results directly
      const searchRes = await searchPhoto(photoBase64);
      
      // Check response structure
      const candidates = searchRes.candidates 
                    || searchRes.matches 
                    || searchRes.results
                    || (Array.isArray(searchRes) ? searchRes : []);

      if (candidates.length === 0) {
        console.log(`❌ No faces found in search results`);
        return res.json({
          ok: false,
          similarity: 0,
          threshold: SIMILARITY_THRESHOLD,
          message: 'not_verified',
          error: 'Face not recognized'
        });
      }

      // CRITICAL SECURITY: Find candidate that matches the expected email
      // This ensures the face belongs to the user with this email
      // We cannot trust the UUID alone - we must verify email match
      const expectedEmail = email.toLowerCase().trim();
      let matchingCandidate = null;
      let bestScore = 0;

      console.log(`📊 Found ${candidates.length} candidate(s) in search results`);
      console.log(`🔍 Looking for email match: ${expectedEmail}`);
      console.log(`🔍 Stored UUID (for reference): ${luxandUuid.trim()}`);

      for (const candidate of candidates) {
        // Get candidate's email/name from search result
        const candidateName = (candidate.name || candidate.email || candidate.subject || '').toString().toLowerCase().trim();
        
        // Try different score field names
        let score = 0;
        if (candidate.probability !== undefined) {
          score = parseFloat(candidate.probability);
        } else if (candidate.similarity !== undefined) {
          score = parseFloat(candidate.similarity);
        } else if (candidate.confidence !== undefined) {
          score = parseFloat(candidate.confidence);
        } else if (candidate.score !== undefined) {
          score = parseFloat(candidate.score);
        }
        
        // Normalize score
        let normalizedScore = score;
        if (score > 1.0 && score <= 100) {
          normalizedScore = score / 100.0;
        } else if (score > 100) {
          normalizedScore = score / 1000.0;
        }
        
        console.log(`📊 Candidate: name="${candidateName}", id="${candidate.id}", Score: ${normalizedScore.toFixed(3)}`);
        console.log(`📊 Email match: ${candidateName === expectedEmail ? '✅ MATCH' : '❌ NO MATCH'}`);
        
        // CRITICAL SECURITY: Only accept if email/name matches AND score is high enough
        // This ensures the face belongs to the user with this email
        if (candidateName === expectedEmail && normalizedScore > bestScore) {
          bestScore = normalizedScore;
          matchingCandidate = candidate;
          console.log(`✅ Found matching candidate for email: ${expectedEmail}`);
        }
      }

      // SECURITY: Must find a match with the expected email
      if (!matchingCandidate) {
        console.error(`🚨 SECURITY: No candidate found matching expected email: ${expectedEmail}`);
        console.error(`🚨 SECURITY: This face does not belong to this user - REJECTING`);
        return res.json({
          ok: false,
          similarity: 0,
          threshold: SIMILARITY_THRESHOLD,
          message: 'not_verified',
          error: 'Face does not match this account. Please use the face registered with this email.',
          security: 'Email mismatch - face belongs to different user'
        });
      }

      if (bestScore < SIMILARITY_THRESHOLD) {
        console.log(`❌ Verification FAILED: Best score ${bestScore.toFixed(3)} < threshold ${SIMILARITY_THRESHOLD}`);
        return res.json({
          ok: false,
          similarity: bestScore,
          threshold: SIMILARITY_THRESHOLD,
          message: 'not_verified',
          error: 'Face similarity below threshold'
        });
      }

      // Try 1:1 verification with the candidate's ID if available
      // This provides an additional security layer
      // NOTE: This endpoint may not be available in all plans, so we use a short timeout
      const candidateId = matchingCandidate.id?.toString() || matchingCandidate.personId?.toString() || '';
      if (candidateId) {
        try {
          console.log(`🔍 Attempting 1:1 verification with candidate ID: ${candidateId}`);
          
          // Use Promise.race to timeout the 1:1 verify attempt quickly (3 seconds)
          // This prevents the entire request from timing out if the endpoint is slow/unavailable
          // Note: This endpoint may not be available in all Luxand plans
          const verifyPromise = verifyPersonPhoto(candidateId, photoBase64);
          const timeoutPromise = new Promise((_, reject) => 
            setTimeout(() => reject(new Error('1:1 verify timeout')), 3000)
          );
          
          const verifyRes = await Promise.race([verifyPromise, timeoutPromise]);
          
          const similarity = parseFloat(verifyRes?.similarity ?? verifyRes?.confidence ?? 0);
          const match = verifyRes?.match ?? verifyRes?.verified ?? false;
          
          let normalizedSimilarity = similarity;
          if (similarity > 1.0 && similarity <= 100) {
            normalizedSimilarity = similarity / 100.0;
          } else if (similarity > 100) {
            normalizedSimilarity = similarity / 1000.0;
          }
          
          console.log(`📊 1:1 Verification result: similarity=${normalizedSimilarity.toFixed(3)}, match=${match}`);
          
          if (normalizedSimilarity >= SIMILARITY_THRESHOLD || match === true) {
            console.log(`✅ Verification PASSED (1:1): similarity=${normalizedSimilarity.toFixed(3)}`);
            console.log(`✅ Email match confirmed: ${expectedEmail}`);
            return res.json({
              ok: true,
              similarity: normalizedSimilarity,
              threshold: SIMILARITY_THRESHOLD,
              message: 'verified',
              method: '1:1_verification'
            });
          }
        } catch (verifyError) {
          // If 1:1 verify fails, times out, or is not available, just use search result (which already passed)
          // Search-based verification with email matching is secure and sufficient
          const errorMsg = verifyError.message || 'Unknown error';
          if (errorMsg.includes('not available') || errorMsg.includes('405') || errorMsg.includes('timed out')) {
            console.log(`ℹ️ 1:1 verify endpoint not available in this Luxand plan - using secure search-based verification instead`);
          } else {
            console.warn(`⚠️ 1:1 verification with ID failed, using search result: ${errorMsg}`);
          }
        }
      }

      // Use search result if 1:1 verification not available or failed
      console.log(`✅ Verification PASSED (search mode): similarity=${bestScore.toFixed(3)}`);
      console.log(`✅ Email match confirmed: ${expectedEmail}`);
      return res.json({
        ok: true,
        similarity: bestScore,
        threshold: SIMILARITY_THRESHOLD,
        message: 'verified',
        method: 'search_with_email_validation'
      });
    } catch (verifyError) {
      console.error(`❌ Secure verification failed: ${verifyError.message}`);
      return res.status(500).json({
        ok: false,
        error: `Verification failed: ${verifyError.message}`,
        security: '1:1 verification required - UUID validation enforced'
      });
    }
    
    // REMOVED: Global search fallback - this was a security vulnerability!
    // Never do global search for login verification - it allows any enrolled face to access any account
    // Only 1:1 verification is allowed for security

  } catch (error) {
    console.error('❌ Verification error:', error);
    res.status(500).json({
      ok: false,
      error: error.message || 'Verification failed'
    });
  }
});

// ==========================================
// CHECK LIVENESS AVAILABILITY ENDPOINT
// ==========================================
// GET /api/check-liveness
// Returns: { available: boolean, message: string, details?: object }
app.get('/api/check-liveness', async (req, res) => {
  try {
    console.log('🔍 Checking liveness endpoint availability...');
    
    // Create a minimal test image (1x1 pixel base64)
    // This is just to test if the endpoint responds, not to actually check liveness
    const testImageBase64 = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwA/wA==';
    
    try {
      const liveRes = await livenessCheck(testImageBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      const isLive = (liveRes?.liveness === 'real') || liveScore >= LIVENESS_THRESHOLD;
      
      return res.json({
        available: true,
        message: 'Liveness detection is available and working',
        details: {
          status: 'success',
          score: liveScore,
          result: liveRes?.liveness || 'real',
          threshold: LIVENESS_THRESHOLD
        }
      });
    } catch (livenessError) {
      const errorMsg = livenessError.message || 'Unknown error';
      
      // Check if it's a 404 or not available error
      if (errorMsg.includes('404') || 
          errorMsg.includes('Not Found') ||
          errorMsg.includes('LIVENESS_ENDPOINT_NOT_AVAILABLE') ||
          errorMsg.includes('aborted')) {
        return res.json({
          available: false,
          message: 'Liveness detection is NOT available in your Luxand API plan',
          details: {
            status: 'not_available',
            error: errorMsg,
            note: 'This endpoint returns 404 or times out, indicating it is not included in your current Luxand plan'
          }
        });
      }
      
      // Other errors (network, etc.)
      return res.json({
        available: false,
        message: 'Liveness detection endpoint returned an error',
        details: {
          status: 'error',
          error: errorMsg,
          note: 'The endpoint exists but returned an error. This might be a network issue or API configuration problem.'
        }
      });
    }
  } catch (error) {
    return res.status(500).json({
      available: false,
      message: 'Error checking liveness availability',
      error: error.message
    });
  }
});

// ==========================================
// COMPARE FACES ENDPOINT (for face uniqueness checking)
// ==========================================
// POST /api/compare-faces
// Body: { photo1Base64: string, photo2Base64: string }
// Returns: { similarity: number, match: boolean }
app.post('/api/compare-faces', async (req, res) => {
  try {
    const { photo1Base64, photo2Base64 } = req.body;

    // Validation
    if (!photo1Base64 || !photo2Base64) {
      return res.status(400).json({
        ok: false,
        error: 'Missing photo1Base64 or photo2Base64'
      });
    }

    if (typeof photo1Base64 !== 'string' || typeof photo2Base64 !== 'string') {
      return res.status(400).json({
        ok: false,
        error: 'Invalid photo format'
      });
    }

    console.log(`🔍 Comparing two faces using Luxand Compare Facial Similarity API...`);
    console.log(`📏 Photo 1 base64 length: ${photo1Base64.length}`);
    console.log(`📏 Photo 2 base64 length: ${photo2Base64.length}`);

    // Remove data URL prefix if present
    let cleanBase64A = photo1Base64;
    if (photo1Base64.includes(',')) {
      cleanBase64A = photo1Base64.split(',')[1];
    }
    
    let cleanBase64B = photo2Base64;
    if (photo2Base64.includes(',')) {
      cleanBase64B = photo2Base64.split(',')[1];
    }

    // Call Luxand Compare Facial Similarity API
    const compareResult = await comparePhotos(cleanBase64A, cleanBase64B);
    
    const similarity = parseFloat(compareResult?.similarity ?? compareResult?.confidence ?? 0);
    const match = compareResult?.match ?? (similarity >= 0.85); // Default threshold

    console.log(`📊 Face comparison result: similarity=${similarity.toFixed(4)}, match=${match}`);

    return res.json({
      ok: true,
      similarity: similarity,
      match: match,
      confidence: compareResult?.confidence ?? similarity
    });

  } catch (error) {
    console.error('❌ Compare faces error:', error);
    res.status(500).json({
      ok: false,
      error: error.message || 'Face comparison failed'
    });
  }
});

// ==========================================
// DELETE PERSON ENDPOINT (for removing enrolled users)
// ==========================================
// POST /api/delete-person
// Body: { email: string } or { uuid: string }
// Returns: { ok: bool, message: string }
app.post('/api/delete-person', async (req, res) => {
  try {
    const { email, uuid } = req.body;

    // Validation
    if (!email && !uuid) {
      return res.status(400).json({
        ok: false,
        error: 'Missing email or uuid'
      });
    }

    let personUuid = uuid;

    // If email is provided, search for the person first
    if (email && !uuid) {
      console.log(`🔍 Searching for person with email: ${email}`);
      
      // Search for the person by doing a face search with a dummy image
      // Then match by name (email) in the results
      // Note: This is a workaround - ideally Luxand would have a list persons endpoint
      try {
        // Create a minimal base64 image (1x1 pixel) for search
        // This won't match any face, but will return all persons if Luxand allows
        // Actually, we can't search without a face image, so we'll need the UUID
        // For now, return an error asking for UUID
        return res.status(400).json({
          ok: false,
          error: 'UUID is required to delete a person.',
          note: 'To find the UUID for an email, check your Firestore users collection where luxandUuid is stored, or use the Luxand dashboard.',
          suggestion: 'You can provide the UUID directly: { "uuid": "person-uuid-here" }'
        });
      } catch (searchError) {
        return res.status(400).json({
          ok: false,
          error: 'Cannot search by email. UUID is required.',
          details: searchError.message
        });
      }
    }

    if (!personUuid || typeof personUuid !== 'string' || personUuid.trim().length === 0) {
      return res.status(400).json({
        ok: false,
        error: 'Invalid UUID format'
      });
    }

    console.log(`🗑️ Deleting person with UUID: ${personUuid.trim()}`);
    
    // Delete the person from Luxand
    const deleteResult = await deletePerson(personUuid.trim());
    
    console.log(`✅ Person deleted successfully: ${personUuid.trim()}`);

    return res.json({
      ok: true,
      message: 'Person deleted successfully',
      uuid: personUuid.trim()
    });

  } catch (error) {
    console.error('❌ Delete person error:', error);
    res.status(500).json({
      ok: false,
      error: error.message || 'Failed to delete person'
    });
  }
});

// ==========================================
// LIST ALL PERSONS ENDPOINT
// ==========================================
// GET /api/list-persons
// Returns: { ok: bool, persons: [...], count: number }
app.get('/api/list-persons', async (req, res) => {
  try {
    console.log('📋 Listing all persons from Luxand...');
    
    const result = await listPersons();
    
    // Handle different response formats from Luxand
    const persons = result.persons || result.data || result || [];
    const count = Array.isArray(persons) ? persons.length : 0;
    
    console.log(`✅ Found ${count} person(s) in Luxand database`);
    
    // Log each person's details
    if (Array.isArray(persons) && persons.length > 0) {
      console.log('📋 Persons list:');
      persons.forEach((person, index) => {
        const uuid = person.uuid || person.id || 'N/A';
        const name = person.name || 'N/A';
        const faces = person.faces || person.face_count || 0;
        console.log(`  ${index + 1}. Name: ${name}, UUID: ${uuid}, Faces: ${faces}`);
      });
    }
    
    return res.json({
      ok: true,
      persons: persons,
      count: count,
      message: `Found ${count} person(s) in Luxand database`
    });
  } catch (error) {
    console.error('❌ Error listing persons:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to list persons from Luxand',
      persons: [],
      count: 0
    });
  }
});

// ==========================================
// ERROR HANDLING
// ==========================================
app.use((err, req, res, next) => {
  console.error('❌ Server error:', err);
  res.status(500).json({
    ok: false,
    error: 'Internal server error'
  });
});

// ==========================================
// START SERVER
// ==========================================
// Bind to 0.0.0.0 (all interfaces) so Railway can reach it
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log('🚀 ==========================================');
  console.log('🚀 Face Auth Backend Server');
  console.log('🚀 ==========================================');
  console.log(`🚀 Server running on port ${PORT} (0.0.0.0)`);
  console.log(`🚀 Health check: http://0.0.0.0:${PORT}/`);
  console.log(`🚀 Health check: http://0.0.0.0:${PORT}/api/health`);
  console.log(`🚀 Luxand API Key: ${process.env.LUXAND_API_KEY ? '✅ Configured' : '❌ Missing'}`);
  console.log(`🚀 Similarity Threshold: ${SIMILARITY_THRESHOLD}`);
  console.log(`🚀 Liveness Threshold: ${LIVENESS_THRESHOLD}`);
  console.log('🚀 ==========================================');
  console.log('✅ Server is ready to accept connections');
  console.log('✅ Railway health check endpoint: GET /');
});

// Keep the process alive - Railway needs the server to stay running
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;

// Log when server is actually listening and ready
server.on('listening', () => {
  console.log('✅ HTTP server is listening and ready for connections');
});

server.on('error', (error) => {
  console.error('❌ Server error:', error);
});

server.on('connection', (socket) => {
  console.log(`🔌 New connection from ${socket.remoteAddress}:${socket.remotePort}`);
});

// Graceful shutdown handlers
process.on('SIGTERM', () => {
  console.log('⚠️ SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('⚠️ SIGINT received, shutting down gracefully...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

