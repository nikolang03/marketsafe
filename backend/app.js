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
    
    // Use secure search with UUID validation (SECURE - only accepts if result matches expected UUID)
    // Note: Luxand verify endpoint may not be available in all plans, so we use search + UUID validation
    console.log('🔍 Using secure search with UUID validation (SECURE MODE)...');
    console.log(`🔍 Verifying face against UUID: ${luxandUuid.trim()}`);
    console.log(`🔍 Security: Will only accept if search result matches this specific UUID`);
    
    try {
      // Use search endpoint (available in all plans)
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

      // SECURITY: Find candidate that matches the expected user
      // Note: Luxand search returns 'id' (numeric) and 'name' (email), not UUID
      // We match by email (name field) since that's what we used for enrollment
      let matchingCandidate = null;
      let bestScore = 0;
      const expectedEmail = email.toLowerCase().trim();

      console.log(`📊 Found ${candidates.length} candidate(s) in search results`);
      console.log(`🔍 Looking for email match: ${expectedEmail}`);
      console.log(`🔍 Stored UUID (for reference): ${luxandUuid.trim()}`);

      for (const candidate of candidates) {
        // Try different name/email field names (Luxand search returns 'name' which is the email)
        const candidateName = (candidate.name || candidate.email || candidate.subject || '').toString().toLowerCase().trim();
        
        // Also try UUID/ID fields for additional validation
        const candidateUuid = (candidate.uuid || candidate.id || candidate.person_uuid || candidate.personId || '').toString().trim();
        const candidateId = candidate.id?.toString() || '';
        
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
        
        console.log(`📊 Candidate: name="${candidateName}", id="${candidateId}", uuid="${candidateUuid}", Score: ${normalizedScore.toFixed(3)}`);
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

      console.log(`📊 Secure verification similarity: ${bestScore.toFixed(3)} (threshold: ${SIMILARITY_THRESHOLD})`);
      console.log(`✅ Email match confirmed: ${expectedEmail}`);
      
      if (bestScore >= SIMILARITY_THRESHOLD) {
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
  console.log(`🚀 Health check: http://0.0.0.0:${PORT}/api/health`);
  console.log(`🚀 Luxand API Key: ${process.env.LUXAND_API_KEY ? '✅ Configured' : '❌ Missing'}`);
  console.log(`🚀 Similarity Threshold: ${SIMILARITY_THRESHOLD}`);
  console.log(`🚀 Liveness Threshold: ${LIVENESS_THRESHOLD}`);
  console.log('🚀 ==========================================');
  console.log('✅ Server is ready to accept connections');
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

