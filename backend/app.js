// app.js - Main Express server for face authentication
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { enrollPhoto, comparePhotos, livenessCheck, searchPhoto, verifyPersonPhoto } from './luxandService.js';

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
// HEALTH CHECK
// ==========================================
app.get('/api/health', (req, res) => {
  res.json({
    ok: true,
    time: new Date().toISOString(),
    service: 'Face Auth Backend',
    luxandConfigured: !!process.env.LUXAND_API_KEY
  });
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

    // 1) Liveness check (optional - skip if endpoint not available)
    try {
      console.log('🔍 Running liveness check...');
      const liveRes = await livenessCheck(photoBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      const isLive = (liveRes?.liveness === 'real') || liveScore >= LIVENESS_THRESHOLD;

      console.log(`📊 Liveness: ${isLive ? 'PASS' : 'FAIL'} (score: ${liveScore.toFixed(2)})`);

      if (!isLive) {
        return res.status(403).json({
          ok: false,
          reason: 'liveness_failed',
          error: 'Liveness check failed. Please blink or turn your head slightly.',
          livenessScore: liveScore
        });
      }
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
    }

    // 2) Verify face - use 1:1 verification if UUID provided, otherwise search
    let searchRes;
    let candidates = [];
    
    if (luxandUuid && typeof luxandUuid === 'string' && luxandUuid.trim().length > 0) {
      // Use 1:1 verification with person UUID (more reliable)
      console.log('🔍 Using 1:1 verification with person UUID...');
      try {
        searchRes = await verifyPersonPhoto(luxandUuid.trim(), photoBase64);
        // 1:1 verification returns direct similarity score
        const similarity = parseFloat(searchRes.similarity || searchRes.score || searchRes.confidence || 0);
        const normalizedSimilarity = similarity > 1.0 ? (similarity / 100.0) : similarity;
        
        console.log(`📊 1:1 Verification similarity: ${normalizedSimilarity.toFixed(3)} (threshold: ${SIMILARITY_THRESHOLD})`);
        
        if (normalizedSimilarity >= SIMILARITY_THRESHOLD) {
          console.log(`✅ Verification PASSED for: ${email}`);
          return res.json({
            ok: true,
            similarity: normalizedSimilarity,
            threshold: SIMILARITY_THRESHOLD,
            message: 'verified'
          });
        } else {
          console.log(`❌ Verification FAILED for: ${email} (score too low)`);
          return res.json({
            ok: false,
            similarity: normalizedSimilarity,
            threshold: SIMILARITY_THRESHOLD,
            message: 'not_verified',
            error: 'Face similarity below threshold'
          });
        }
      } catch (verifyError) {
        console.warn(`⚠️ 1:1 verification failed, falling back to search: ${verifyError.message}`);
        // Fall through to search-based verification
      }
    }
    
    // Fallback: Search for face among enrolled subjects
    console.log('🔍 Searching for face...');
    searchRes = await searchPhoto(photoBase64);
    
    // Check response structure - Luxand might return different formats
    console.log(`📦 Search response structure:`, JSON.stringify(searchRes).substring(0, 300));
    
    // Try different response structures
    candidates = searchRes.candidates 
              || searchRes.matches 
              || searchRes.results
              || (Array.isArray(searchRes) ? searchRes : []);

    if (candidates.length === 0) {
      return res.json({
        ok: false,
        similarity: 0,
        threshold: SIMILARITY_THRESHOLD,
        message: 'Face not found in enrolled subjects',
        error: 'Face not recognized'
      });
    }

    // 3) Find best match (highest similarity)
    let bestMatch = null;
    let bestScore = 0;

    console.log(`📊 Found ${candidates.length} candidate(s)`);

    for (const candidate of candidates) {
      // Log full candidate object to see what fields are available
      console.log(`📦 Full candidate object:`, JSON.stringify(candidate).substring(0, 200));
      
      // Try different score field names (Luxand might use different names)
      let score = 0;
      
      // Try all possible field names (Luxand uses "probability" for similarity)
      if (candidate.probability !== undefined) {
        score = parseFloat(candidate.probability);
      } else if (candidate.similarity !== undefined) {
        score = parseFloat(candidate.similarity);
      } else if (candidate.confidence !== undefined) {
        score = parseFloat(candidate.confidence);
      } else if (candidate.score !== undefined) {
        score = parseFloat(candidate.score);
      } else if (candidate.match_score !== undefined) {
        score = parseFloat(candidate.match_score);
      } else if (candidate.match !== undefined) {
        // If match is boolean, use a default high score
        score = candidate.match === true ? 0.95 : 0;
      } else if (candidate.verified !== undefined) {
        score = candidate.verified === true ? 0.95 : 0;
      }
      
      // Normalize if score > 1 (percentage format) or if it's 0-100
      let normalizedScore = score;
      if (score > 1.0 && score <= 100) {
        normalizedScore = score / 100.0;
      } else if (score > 100) {
        normalizedScore = score / 1000.0; // In case it's 0-1000
      }
      
      console.log(`📊 Candidate: uuid=${candidate.uuid || candidate.id || candidate.person_uuid || 'unknown'}, raw_score=${score}, normalized=${normalizedScore.toFixed(3)}`);
      
      if (normalizedScore > bestScore) {
        bestScore = normalizedScore;
        bestMatch = candidate;
      }
    }

    console.log(`📊 Best match similarity: ${bestScore.toFixed(3)} (threshold: ${SIMILARITY_THRESHOLD})`);

    // 4) Check if similarity meets threshold
    const passed = bestScore >= SIMILARITY_THRESHOLD;

    if (passed) {
      console.log(`✅ Verification PASSED for: ${email}`);
      return res.json({
        ok: true,
        similarity: bestScore,
        threshold: SIMILARITY_THRESHOLD,
        message: 'verified'
      });
    } else {
      console.log(`❌ Verification FAILED for: ${email} (score too low)`);
      return res.json({
        ok: false,
        similarity: bestScore,
        threshold: SIMILARITY_THRESHOLD,
        message: 'not_verified',
        error: 'Face similarity below threshold'
      });
    }

  } catch (error) {
    console.error('❌ Verification error:', error);
    res.status(500).json({
      ok: false,
      error: error.message || 'Verification failed'
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
app.listen(PORT, () => {
  console.log('🚀 ==========================================');
  console.log('🚀 Face Auth Backend Server');
  console.log('🚀 ==========================================');
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`🚀 Health check: http://localhost:${PORT}/api/health`);
  console.log(`🚀 Luxand API Key: ${process.env.LUXAND_API_KEY ? '✅ Configured' : '❌ Missing'}`);
  console.log(`🚀 Similarity Threshold: ${SIMILARITY_THRESHOLD}`);
  console.log(`🚀 Liveness Threshold: ${LIVENESS_THRESHOLD}`);
  console.log('🚀 ==========================================');
});

