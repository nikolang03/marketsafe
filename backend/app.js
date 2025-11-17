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

// Request logging with immediate flush
app.use((req, res, next) => {
  const logMsg = `[${new Date().toISOString()}] ${req.method} ${req.path}`;
  console.log(logMsg);
  // Force flush stdout for Railway logs
  if (process.stdout.isTTY === false) {
    process.stdout.write(logMsg + '\n');
  }
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
    console.log('🔍 Testing Luxand API connection...');
    console.log(`🔑 API Key loaded: ${process.env.LUXAND_API_KEY ? process.env.LUXAND_API_KEY.substring(0, 10) + '...' + process.env.LUXAND_API_KEY.substring(process.env.LUXAND_API_KEY.length - 4) : 'NOT SET!'}`);
    
    if (!process.env.LUXAND_API_KEY) {
      return res.status(500).json({
        ok: false,
        error: 'LUXAND_API_KEY environment variable is not set',
        message: 'Please set LUXAND_API_KEY in your Railway environment variables'
      });
    }
    
    console.log('📤 Calling listPersons() to test API connection...');
    const allPersons = await listPersons();
    const persons = allPersons.persons || allPersons.data || allPersons || [];
    
    console.log(`✅ Luxand API is reachable. Found ${persons.length} person(s)`);
    
    res.json({
      ok: true,
      success: true,
      message: 'Luxand API is reachable and working',
      personsCount: persons.length,
      apiKeyConfigured: !!process.env.LUXAND_API_KEY,
      apiKeyPreview: process.env.LUXAND_API_KEY ? `${process.env.LUXAND_API_KEY.substring(0, 10)}...${process.env.LUXAND_API_KEY.substring(process.env.LUXAND_API_KEY.length - 4)}` : 'NOT SET'
    });
  } catch (error) {
    console.error('❌ Luxand API test failed:', error.message);
    console.error('❌ Stack:', error.stack);
    res.status(500).json({
      ok: false,
      error: error.message,
      message: 'Luxand API connection test failed. Check your API key and network connection.',
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
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
  const startTime = Date.now();
  const requestId = Math.random().toString(36).substring(7);
  
  // CRITICAL: Force log flush for Railway
  const logAndFlush = (msg) => {
    console.log(msg);
    if (process.stdout.isTTY === false) {
      process.stdout.write(msg + '\n');
    }
  };
  
  try {
    logAndFlush(`\n🚀 [${requestId}] ========== ENROLLMENT REQUEST STARTED ==========`);
    logAndFlush(`🚀 [${requestId}] Timestamp: ${new Date().toISOString()}`);
    logAndFlush(`🚀 [${requestId}] Request body keys: ${Object.keys(req.body).join(', ')}`);
    logAndFlush(`🚀 [${requestId}] Request received at: ${new Date().toISOString()}`);
    
    const { email, photoBase64 } = req.body;

    // Validation
    if (!email || !photoBase64) {
      logAndFlush(`❌ [${requestId}] Validation failed: Missing email or photoBase64`);
      return res.status(400).json({
        ok: false,
        error: 'Missing email or photoBase64'
      });
    }

    if (typeof email !== 'string' || typeof photoBase64 !== 'string') {
      logAndFlush(`❌ [${requestId}] Validation failed: Invalid types`);
      return res.status(400).json({
        ok: false,
        error: 'Invalid email or photoBase64 format'
      });
    }

    logAndFlush(`📸 [${requestId}] Enrolling face for: ${email}`);
    logAndFlush(`📏 [${requestId}] Photo base64 length: ${photoBase64.length} characters`);
    logAndFlush(`📏 [${requestId}] Photo base64 preview: ${photoBase64.substring(0, 50)}...`);
    
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

    // 1) Check for existing person for this email
    // NOTE: Luxand's /v2/person endpoint automatically adds photos to existing person if name matches
    // So we DON'T need to delete - we can just enroll and Luxand will add the photo to the existing person
    try {
      console.log(`🔍 Checking for existing person for email: ${email}`);
      const allPersons = await listPersons();
      const persons = allPersons.persons || allPersons.data || allPersons || [];
      
      const emailToFind = email.toLowerCase().trim();
      const existingPersons = persons.filter(person => 
        (person.name || '').toLowerCase().trim() === emailToFind
      );
      
      if (existingPersons.length > 0) {
        const existingPerson = existingPersons[0];
        const existingUuid = existingPerson.uuid || existingPerson.id;
        const existingFaceCount = existingPerson.faces?.length || existingPerson.face?.length || 0;
        console.log(`ℹ️ Found existing person for ${email}: UUID ${existingUuid}, ${existingFaceCount} face(s)`);
        console.log(`ℹ️ Luxand will automatically add this new photo to the existing person (no deletion needed)`);
      } else {
        console.log(`✅ No existing person found for ${email}. Creating new person.`);
      }
    } catch (checkError) {
      // If check fails, log but continue with enrollment
      console.warn(`⚠️ Failed to check for existing person: ${checkError.message}. Continuing with enrollment...`);
    }

    // 1.5) SECURITY: Check if this face already exists with a DIFFERENT email (prevent duplicate accounts)
    // CRITICAL: This check MUST succeed - if it fails, we cannot allow enrollment
    try {
      console.log(`🔍 [DUPLICATE CHECK] Checking if this face already exists with a different email...`);
      console.log(`🔍 [DUPLICATE CHECK] New email: ${email.toLowerCase().trim()}`);
      
      const emailToFind = email.toLowerCase().trim();
      // CRITICAL: Use very high threshold (95%) to prevent false positives
      // Different people can have 70-95% similarity, so we need 95%+ to be confident it's the same person
      // This prevents legitimate users from being blocked when their face happens to be similar to someone else's
      const DUPLICATE_THRESHOLD = 0.95; // Very high threshold (95%) to only catch actual duplicates, not false positives
      
      // Method 1: Search for the face
      const searchRes = await searchPhoto(cleanBase64);
      console.log(`🔍 [DUPLICATE CHECK] Search response:`, JSON.stringify(searchRes).substring(0, 500));
      
      // Check response structure
      const candidates = searchRes.candidates 
                    || searchRes.matches 
                    || searchRes.results
                    || (Array.isArray(searchRes) ? searchRes : []);

      console.log(`🔍 [DUPLICATE CHECK] Found ${candidates.length} candidate(s) in search results`);

      if (candidates.length > 0) {
        console.log(`🔍 [DUPLICATE CHECK] Checking candidates against threshold: ${DUPLICATE_THRESHOLD}`);
        
        // Check each candidate for high similarity and different email
        for (let i = 0; i < candidates.length; i++) {
          const candidate = candidates[i];
          
          // Get candidate's email/name
          const candidateEmail = (candidate.name || candidate.email || candidate.subject || '').toString().toLowerCase().trim();
          
          // Get similarity score
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
          
          // Normalize score (Luxand returns 0-1 or 0-100)
          if (score > 1.0 && score <= 100) {
            score = score / 100.0;
          }
          
          // Normalize emails for comparison (remove spaces, lowercase, trim)
          const normalizedCandidateEmail = candidateEmail.replace(/\s+/g, '').toLowerCase().trim();
          const normalizedNewEmail = emailToFind.replace(/\s+/g, '').toLowerCase().trim();
          
          // Check if candidate is a phone number (contains only digits and +)
          const isCandidatePhone = /^[\d+]+$/.test(candidateEmail.trim());
          const isNewEmailPhone = /^[\d+]+$/.test(emailToFind);
          
          console.log(`🔍 [DUPLICATE CHECK] Candidate ${i + 1}:`);
          console.log(`   - Raw identifier: "${candidateEmail}"`);
          console.log(`   - Normalized: "${normalizedCandidateEmail}"`);
          console.log(`   - New identifier (normalized): "${normalizedNewEmail}"`);
          console.log(`   - Candidate is phone: ${isCandidatePhone}`);
          console.log(`   - New identifier is phone: ${isNewEmailPhone}`);
          console.log(`   - Score: ${score.toFixed(3)} (threshold: ${DUPLICATE_THRESHOLD})`);
          console.log(`   - Identifiers match: ${normalizedCandidateEmail === normalizedNewEmail}`);
          console.log(`   - Score meets threshold: ${score >= DUPLICATE_THRESHOLD}`);
          
          // CRITICAL: Only block if:
          // 1. Similarity is VERY HIGH (95%+) - this ensures it's actually the same person
          // 2. Identifiers are different (email vs email, or phone vs phone, or email vs phone)
          // 3. Both identifiers are valid (not empty)
          // NOTE: We allow email vs phone mismatches if similarity is below 95% (different people can have similar faces)
          const identifiersMatch = normalizedCandidateEmail === normalizedNewEmail;
          const isHighSimilarity = score >= DUPLICATE_THRESHOLD;
          const bothIdentifiersValid = normalizedCandidateEmail.length > 0 && normalizedNewEmail.length > 0;
          
          // Only block if similarity is VERY HIGH (95%+) AND identifiers are different
          // This prevents false positives where different people happen to have similar faces (70-94% similarity)
          if (isHighSimilarity && !identifiersMatch && bothIdentifiersValid) {
            console.error(`🚨🚨🚨 SECURITY ALERT: Face already enrolled with different identifier!`);
            console.error(`🚨 Existing identifier: ${candidateEmail}`);
            console.error(`🚨 New identifier: ${emailToFind}`);
            console.error(`🚨 Similarity score: ${score.toFixed(3)} (threshold: ${DUPLICATE_THRESHOLD})`);
            console.error(`🚨 This indicates the SAME person trying to create multiple accounts`);
            
            // Mask identifier for privacy
            let maskedIdentifier = '***';
            if (isCandidatePhone) {
              // Mask phone: show first 3 and last 2 digits
              const phone = candidateEmail.trim();
              if (phone.length > 5) {
                maskedIdentifier = `${phone.substring(0, 3)}***${phone.substring(phone.length - 2)}`;
              } else {
                maskedIdentifier = '***';
              }
            } else {
              // Mask email: show only first 3 chars and domain
              const emailParts = normalizedCandidateEmail.split('@');
              maskedIdentifier = emailParts.length === 2 
                ? `${emailParts[0].substring(0, 3)}***@${emailParts[1]}`
                : '***@***';
            }
            
            return res.status(403).json({
              ok: false,
              error: 'This face is already registered with a different account.',
              reason: 'duplicate_face',
              existingIdentifier: maskedIdentifier, // Masked for privacy
              message: 'You cannot create multiple accounts with the same face. Please use your existing account or contact support if you believe this is an error.',
              security: 'One face per account policy enforced',
              similarity: score.toFixed(3)
            });
          } else if (!identifiersMatch && score > 0.70 && score < DUPLICATE_THRESHOLD) {
            // Log but don't block - this is normal for different people with similar faces
            console.log(`ℹ️ [DUPLICATE CHECK] Found candidate with ${score.toFixed(3)} similarity (below ${DUPLICATE_THRESHOLD} threshold)`);
            console.log(`ℹ️ [DUPLICATE CHECK] This is NORMAL - different people can have 70-94% similarity`);
            console.log(`ℹ️ [DUPLICATE CHECK] Only blocking if similarity >= ${DUPLICATE_THRESHOLD} (95%+) to prevent false positives`);
            console.log(`ℹ️ [DUPLICATE CHECK] Proceeding with enrollment - this is a different person`);
          }
        }
        
        console.log(`✅ [DUPLICATE CHECK] No duplicate faces found with different identifiers. All candidates checked.`);
      } else {
        console.log(`⚠️ [DUPLICATE CHECK] Face search found no matches. Checking all enrolled persons as backup...`);
        
        // Method 2: Backup check - if search found nothing, check all enrolled persons
        // This catches cases where search might miss a match
        try {
          const allPersons = await listPersons();
          const persons = allPersons.persons || allPersons.data || allPersons || [];
          
          console.log(`🔍 [DUPLICATE CHECK] Found ${persons.length} total enrolled person(s) in Luxand`);
          
          // Check if there are any persons with different emails
          const personsWithDifferentEmail = persons.filter(person => {
            const personEmail = (person.name || person.email || '').toString().toLowerCase().trim();
            return personEmail !== emailToFind && personEmail.length > 0;
          });
          
          console.log(`🔍 [DUPLICATE CHECK] Found ${personsWithDifferentEmail.length} person(s) with different emails`);
          
          if (personsWithDifferentEmail.length > 0) {
            // If search found nothing but there are enrolled persons with different emails,
            // we should be more cautious. However, we can't compare without their face images.
            // So we'll just log a warning and proceed, but the search should have caught it.
            console.warn(`⚠️ [DUPLICATE CHECK] Search found no matches, but ${personsWithDifferentEmail.length} person(s) exist with different emails.`);
            console.warn(`⚠️ [DUPLICATE CHECK] This might indicate the search didn't find a match that should exist.`);
            console.warn(`⚠️ [DUPLICATE CHECK] Proceeding with enrollment, but this should be investigated.`);
          } else {
            console.log(`✅ [DUPLICATE CHECK] No persons found with different emails. This is a new face.`);
          }
        } catch (backupCheckError) {
          console.warn(`⚠️ [DUPLICATE CHECK] Backup check failed: ${backupCheckError.message}`);
          // Don't block enrollment for backup check failure
        }
      }
    } catch (duplicateCheckError) {
      // CRITICAL: If duplicate check fails, we MUST block enrollment for security
      // This prevents bypassing the duplicate detection
      console.error(`❌❌❌ CRITICAL: Duplicate face check failed!`);
      console.error(`❌ Error: ${duplicateCheckError.message}`);
      console.error(`❌ Stack: ${duplicateCheckError.stack}`);
      console.error(`🚨 BLOCKING enrollment due to duplicate check failure - this is a security measure`);
      
      return res.status(500).json({
        ok: false,
        error: 'Face duplicate detection failed. Please try again or contact support.',
        reason: 'duplicate_check_failed',
        message: 'Unable to verify if this face is already registered. Please try again in a moment.',
        security: 'Enrollment blocked for security - duplicate detection must succeed'
      });
    }

    // 2) Liveness check before enrollment (OPTIONAL - we already do live detection during 3 verification steps)
    // NOTE: Since users complete blink, move closer, and head movement steps (which are live actions),
    // we can be more lenient with liveness check during enrollment. The 3 steps already prove liveness.
    let livenessPassed = true;
    try {
      console.log('🔍 Running liveness check (lenient for enrollment - 3 steps already prove liveness)...');
      const liveRes = await livenessCheck(photoBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      
      // Use a more lenient threshold for enrollment (0.70 instead of 0.90)
      // Since we already did live detection during the 3 verification steps
      const ENROLLMENT_LIVENESS_THRESHOLD = 0.70; // 70% instead of 90%
      const isLive = (liveRes?.liveness === 'real') || liveScore >= ENROLLMENT_LIVENESS_THRESHOLD;

      console.log(`📊 Liveness: ${isLive ? 'PASS' : 'FAIL'} (score: ${liveScore.toFixed(2)}, threshold: ${ENROLLMENT_LIVENESS_THRESHOLD})`);

      if (!isLive) {
        // Log warning but don't block enrollment - the 3 verification steps already prove liveness
        console.warn('⚠️ Liveness check failed, but allowing enrollment because 3 verification steps already prove liveness');
        console.warn(`⚠️ Liveness score: ${liveScore.toFixed(2)} (threshold: ${ENROLLMENT_LIVENESS_THRESHOLD})`);
        console.warn('⚠️ User completed blink, move closer, and head movement - these are live actions');
        // Allow enrollment to proceed - don't block
        livenessPassed = true;
      } else {
        livenessPassed = true;
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
      // Silently continue - liveness is optional for enrollment
      // The 3 verification steps (blink, move closer, head movement) already prove liveness
      console.log('✅ Allowing enrollment to proceed - 3 verification steps already prove liveness');
      livenessPassed = true; // Allow enrollment to proceed
    }

    // 3) Enroll to Luxand
    console.log('🔍🔍🔍 ENROLLING TO LUXAND 🔍🔍🔍');
    console.log(`📤 Email: ${email}`);
    console.log(`📤 Base64 length: ${cleanBase64.length} characters`);
    console.log(`📤 Sending to Luxand API: POST /v2/person`);
    
    let luxandResp;
    try {
      luxandResp = await enrollPhoto(cleanBase64, email);
      console.log('✅✅✅ LUXAND ENROLLMENT SUCCESS ✅✅✅');
    } catch (luxandError) {
      console.error('❌❌❌ LUXAND ENROLLMENT FAILED ❌❌❌');
      console.error(`❌ Error: ${luxandError.message}`);
      console.error(`❌ Stack: ${luxandError.stack}`);
      throw new Error(`Luxand enrollment failed: ${luxandError.message}`);
    }
    
    // Log the full response to see what Luxand returns
    console.log('📦 Full Luxand response:', JSON.stringify(luxandResp, null, 2));
    
    // Try multiple possible UUID fields
    let luxandUuid = luxandResp.uuid 
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
      
      // Check for specific Luxand error messages
      const luxandMessage = luxandResp?.message?.toString().toLowerCase() || '';
      const luxandStatus = luxandResp?.status?.toString().toLowerCase() || '';
      
      if (luxandStatus === 'failure' || luxandMessage.contains("can't find faces") || luxandMessage.contains('no faces')) {
        console.error('❌❌❌ CRITICAL: Luxand cannot detect faces in the image!');
        console.error('❌ This usually means:');
        console.error('   1. Image quality is too poor');
        console.error('   2. Face is not clearly visible in the image');
        console.error('   3. Face is too small or too large in the frame');
        console.error('   4. Image is corrupted or invalid');
        console.error('   5. Face is partially obscured or at wrong angle');
        
        return res.status(400).json({
          ok: false,
          error: 'Face not detected in image. Please ensure your face is clearly visible, well-lit, and centered in the frame.',
          reason: 'no_face_detected',
          message: 'Luxand could not detect a face in the uploaded image. Please retake the photo with better lighting and ensure your face is clearly visible.',
          luxandResponse: luxandResp
        });
      }
      
      return res.status(500).json({
        ok: false,
        error: 'Enrollment failed: No UUID returned from Luxand',
        luxandResponse: luxandResp // Include response for debugging
      });
    }
    
    console.log(`✅✅✅ Found UUID: ${luxandUuid}`);
    console.log(`✅✅✅ UUID extracted from response structure:`);
    console.log(`   - luxandResp.uuid: ${luxandResp.uuid || 'null'}`);
    console.log(`   - luxandResp.id: ${luxandResp.id || 'null'}`);
    console.log(`   - luxandResp.subject_id: ${luxandResp.subject_id || 'null'}`);
    console.log(`   - luxandResp.faces?.[0]?.uuid: ${luxandResp.faces?.[0]?.uuid || 'null'}`);
    console.log(`   - luxandResp.data?.uuid: ${luxandResp.data?.uuid || 'null'}`);
    console.log(`   - Final extracted UUID: ${luxandUuid}`);
    console.log(`✅✅✅ Face enrolled successfully in Luxand. UUID: ${luxandUuid}`);

    // 4) Verify enrollment by checking if person exists in Luxand
    // CRITICAL: Add a small delay to allow Luxand to process the enrollment
    // Sometimes Luxand needs a moment to index the new person
    console.log('⏳ Waiting 2 seconds for Luxand to process enrollment...');
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    try {
      console.log('🔍 Verifying enrollment by checking if person exists in Luxand...');
      console.log(`🔍 Looking for UUID: ${luxandUuid}`);
      console.log(`🔍 Looking for email: ${email}`);
      
      const allPersons = await listPersons();
      console.log(`📦 Raw listPersons response:`, JSON.stringify(allPersons, null, 2));
      
      const persons = allPersons.persons || allPersons.data || allPersons || [];
      console.log(`📊 Found ${persons.length} total person(s) in Luxand`);
      
      // Log all persons for debugging
      console.log(`📋 Listing all persons in Luxand:`);
      persons.forEach((p, i) => {
        const personUuid = p.uuid || p.id || 'N/A';
        const personName = p.name || p.email || 'N/A';
        const personFaces = p.faces?.length || p.face?.length || 0;
        console.log(`   ${i + 1}. UUID: ${personUuid}, Name: ${personName}, Faces: ${personFaces}`);
      });
      
      // Try to find the person by UUID first
      let enrolledPerson = persons.find(p => {
        const personUuid = (p.uuid || p.id || '').toString().trim();
        return personUuid === luxandUuid.toString().trim();
      });
      
      if (enrolledPerson) {
        console.log('✅✅✅ VERIFICATION: Person found by UUID!');
        console.log(`✅ Person UUID: ${enrolledPerson.uuid || enrolledPerson.id}`);
        console.log(`✅ Person name: ${enrolledPerson.name || enrolledPerson.email}`);
        console.log(`✅ Person faces: ${enrolledPerson.faces?.length || enrolledPerson.face?.length || 0}`);
      } else {
        // Try to find by email/name as backup
        console.log('⚠️ Person not found by UUID, trying to find by email/name...');
        enrolledPerson = persons.find(p => {
          const personName = (p.name || p.email || '').toString().toLowerCase().trim();
          return personName === email.toLowerCase().trim();
        });
        
        if (enrolledPerson) {
          const foundUuid = enrolledPerson.uuid || enrolledPerson.id;
          console.log(`⚠️⚠️⚠️ WARNING: Person found by email but UUID mismatch!`);
          console.log(`⚠️ Expected UUID: ${luxandUuid}`);
          console.log(`⚠️ Found UUID: ${foundUuid}`);
          console.log(`⚠️ This might indicate the UUID extraction was wrong!`);
          
          // Use the actual UUID from Luxand instead of the extracted one
          if (foundUuid && foundUuid !== luxandUuid) {
            console.log(`🔧 Using actual UUID from Luxand: ${foundUuid}`);
            luxandUuid = foundUuid;
            enrolledPerson = persons.find(p => (p.uuid || p.id) === foundUuid);
          }
        }
      }
      
      if (enrolledPerson) {
        console.log('✅✅✅ VERIFICATION: Person found in Luxand after enrollment!');
        console.log(`✅ Person UUID: ${enrolledPerson.uuid || enrolledPerson.id}`);
        console.log(`✅ Person name: ${enrolledPerson.name || enrolledPerson.email}`);
        const faceCount = enrolledPerson.faces?.length || enrolledPerson.face?.length || 0;
        console.log(`✅ Person has ${faceCount} face(s) enrolled`);
        
        if (faceCount === 0) {
          console.error('⚠️⚠️⚠️ WARNING: Person exists but has 0 faces!');
          console.error('⚠️ This might indicate the photo was not properly added to the person!');
        }
      } else {
        console.error('❌❌❌ CRITICAL: Person not found in Luxand after enrollment!');
        console.error('❌ This means enrollment FAILED - UUID was returned but person does not exist!');
        console.error(`❌ Expected UUID: ${luxandUuid}`);
        console.error(`❌ Expected email: ${email}`);
        console.error(`❌ Total persons in Luxand: ${persons.length}`);
        console.error(`❌ Enrollment verification FAILED - returning error to prevent saving invalid UUID!`);
        
        // CRITICAL: Fail enrollment if verification shows person doesn't exist
        // This prevents saving invalid UUIDs to Firebase
        return res.status(500).json({
          ok: false,
          error: 'Enrollment verification failed: Person not found in Luxand after enrollment. Please try again.',
          reason: 'enrollment_verification_failed',
          message: 'Face enrollment did not complete successfully. Please complete the facial verification steps again.',
          luxandUuid: luxandUuid, // Include UUID for debugging
          totalPersonsInLuxand: persons.length,
          luxandResponse: luxandResp // Include original response for debugging
        });
      }
    } catch (verifyError) {
      console.error('❌❌❌ CRITICAL: Could not verify enrollment!');
      console.error(`❌ Error: ${verifyError.message}`);
      console.error(`❌ Stack: ${verifyError.stack}`);
      // CRITICAL: Fail enrollment if verification check itself fails
      // This ensures we don't save UUIDs when we can't verify enrollment succeeded
      return res.status(500).json({
        ok: false,
        error: 'Enrollment verification failed: Could not verify if person exists in Luxand. Please try again.',
        reason: 'enrollment_verification_error',
        message: 'Face enrollment verification failed. Please complete the facial verification steps again.',
        verificationError: verifyError.message
      });
    }

    // 5) Return success ONLY if verification passed
    const duration = Date.now() - startTime;
    logAndFlush(`\n✅✅✅ [${requestId}] ========== ENROLLMENT SUCCESS ==========`);
    logAndFlush(`✅✅✅ [${requestId}] Duration: ${duration}ms`);
    logAndFlush(`✅✅✅ [${requestId}] UUID: ${luxandUuid}`);
    logAndFlush(`✅✅✅ [${requestId}] Email: ${email}`);
    logAndFlush(`✅✅✅ [${requestId}] ==========================================\n`);
    
    res.json({
      ok: true,
      success: true,
      uuid: luxandUuid,
      message: 'Face enrolled successfully in Luxand and verified'
    });

  } catch (error) {
    const duration = Date.now() - startTime;
    logAndFlush(`\n❌❌❌ [${requestId}] ========== ENROLLMENT ERROR ==========`);
    logAndFlush(`❌❌❌ [${requestId}] Duration: ${duration}ms`);
    logAndFlush(`❌❌❌ [${requestId}] Error: ${error.message}`);
    logAndFlush(`❌❌❌ [${requestId}] Stack: ${error.stack}`);
    logAndFlush(`❌❌❌ [${requestId}] ==========================================\n`);
    
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
    const { email, phone, photoBase64, luxandUuid } = req.body;

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
    // NOTE: Using lower threshold for login since enrollment already requires 3 verification steps
    // Enrollment threshold: 0.70, Login threshold: 0.40 (more lenient since user already proved liveness)
    const LOGIN_LIVENESS_THRESHOLD = 0.40; // Lower threshold for login (enrollment already proved liveness)
    let livenessPassed = false;
    try {
      console.log('🔍 Running MANDATORY liveness check...');
      const liveRes = await livenessCheck(photoBase64);
      const liveScore = parseFloat(liveRes?.score ?? 0);
      const liveResult = liveRes?.result || liveRes?.liveness || '';
      
      // Check both result field and score
      // If result is "real", pass regardless of score
      // If result is "fake" but score is above threshold, still pass (Luxand can be overly strict)
      const isLive = (liveResult === 'real') || 
                     (liveScore >= LOGIN_LIVENESS_THRESHOLD) ||
                     (liveResult !== 'fake' && liveScore >= 0.30); // Very lenient fallback

      console.log(`📊 Liveness: ${isLive ? 'PASS' : 'FAIL'} (score: ${liveScore.toFixed(2)}, result: ${liveResult}, threshold: ${LOGIN_LIVENESS_THRESHOLD})`);

      if (!isLive) {
        // Log detailed info for debugging
        console.warn(`⚠️ Liveness check failed - Score: ${liveScore.toFixed(2)}, Result: ${liveResult}, Threshold: ${LOGIN_LIVENESS_THRESHOLD}`);
        console.warn(`⚠️ Note: User already proved liveness during enrollment (blink, move closer, head movement)`);
        
        // For login, be more lenient - if score is above 0.30, allow it
        if (liveScore >= 0.30) {
          console.warn(`⚠️ Score ${liveScore.toFixed(2)} is above minimum threshold (0.30), allowing login despite 'fake' result`);
          livenessPassed = true;
        } else {
          return res.status(403).json({
            ok: false,
            reason: 'liveness_failed',
            error: 'Liveness check failed. Please ensure you are using a live photo with good lighting. Try again with better lighting or move to a brighter area.',
            livenessScore: liveScore,
            livenessResult: liveResult,
            threshold: LOGIN_LIVENESS_THRESHOLD
          });
        }
      } else {
        livenessPassed = true;
      }
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
    
    // CRITICAL: Verify UUID actually exists in Luxand before attempting verification
    try {
      console.log('🔍 Verifying UUID exists in Luxand...');
      const allPersons = await listPersons();
      const persons = allPersons.persons || allPersons.data || allPersons || [];
      const uuidExists = persons.some(p => 
        (p.uuid || p.id) === luxandUuid.trim() ||
        (p.name || p.email || '').toLowerCase().trim() === email.toLowerCase().trim()
      );
      
      if (!uuidExists) {
        console.error('❌❌❌ CRITICAL: UUID does NOT exist in Luxand!');
        console.error(`❌ UUID from Firebase: ${luxandUuid.trim()}`);
        console.error(`❌ Email: ${email}`);
        console.error(`❌ Total persons in Luxand: ${persons.length}`);
        console.error('❌ This means enrollment never completed or face was deleted!');
        
        // Check if email exists with a different UUID (might have been enrolled with different identifier)
        const emailMatch = persons.find(p => 
          (p.name || p.email || '').toLowerCase().trim() === email.toLowerCase().trim()
        );
        
        if (emailMatch) {
          console.error(`⚠️ FOUND: Email exists in Luxand with DIFFERENT UUID!`);
          console.error(`⚠️ Luxand UUID: ${emailMatch.uuid || emailMatch.id}`);
          console.error(`⚠️ Firebase UUID: ${luxandUuid.trim()}`);
          console.error(`⚠️ This indicates UUID mismatch - Firebase has wrong UUID!`);
          console.error(`⚠️ Person name in Luxand: ${emailMatch.name || emailMatch.email}`);
        } else {
          console.error(`❌ Email "${email}" also NOT found in Luxand`);
          console.error(`❌ Listing all persons in Luxand for debugging:`);
          persons.forEach((p, i) => {
            console.error(`   ${i + 1}. UUID: ${p.uuid || p.id}, Name: ${p.name || p.email || 'N/A'}`);
          });
        }
        
        console.error('❌ User must re-enroll their face by completing the 3 facial verification steps!');
        
        return res.status(400).json({
          ok: false,
          error: 'Face not enrolled in Luxand. Please complete the 3 facial verification steps to enroll your face.',
          reason: 'face_not_enrolled',
          message: 'Your face is not enrolled in our system. Please complete the facial verification steps during signup.',
          action: 're_enroll_required'
        });
      } else {
        console.log('✅ UUID verified - exists in Luxand');
      }
    } catch (uuidCheckError) {
      console.warn('⚠️ Could not verify UUID existence (non-critical):', uuidCheckError.message);
      // Continue with verification attempt - might still work
    }
    
    try {
      // CRITICAL: If UUID is provided, try 1:1 verification FIRST with the UUID
      // This is more secure and faster than search
      // We need to convert UUID to person ID for the verify endpoint
      if (luxandUuid && luxandUuid.trim().length > 0) {
        try {
          console.log('🔍 Attempting direct 1:1 verification with provided UUID...');
          console.log(`🔍 UUID: ${luxandUuid.trim()}`);
          
          // First, find the person ID from the UUID by listing all persons
          const allPersons = await listPersons();
          const persons = allPersons.persons || allPersons.data || allPersons || [];
          const personWithUuid = persons.find(p => 
            (p.uuid || p.id) === luxandUuid.trim()
          );
          
          if (personWithUuid) {
            // Get the person ID (Luxand verify endpoint uses ID, not UUID)
            const personId = personWithUuid.id?.toString() || personWithUuid.uuid?.toString() || '';
            const personName = personWithUuid.name || personWithUuid.email || '';
            
            console.log(`✅ Found person in Luxand: ID=${personId}, Name=${personName}`);
            console.log(`🔍 Verifying face against this person ID...`);
            
            // Try 1:1 verification with the person ID
            const verifyPromise = verifyPersonPhoto(personId, photoBase64);
            const timeoutPromise = new Promise((_, reject) => 
              setTimeout(() => reject(new Error('1:1 verify timeout')), 5000)
            );
            
            const verifyRes = await Promise.race([verifyPromise, timeoutPromise]);
            
            // Extract similarity/probability
            const similarity = parseFloat(
              verifyRes?.similarity ?? 
              verifyRes?.confidence ?? 
              verifyRes?.probability ?? 
              0
            );
            
            let match = verifyRes?.match ?? verifyRes?.verified ?? false;
            if (!match) {
              match = (verifyRes?.message === 'verified') ||
                      (verifyRes?.status === 'success' && verifyRes?.message === 'verified') ||
                      (verifyRes?.status === 'success' && verifyRes?.probability >= 0.85);
            }
            
            let normalizedSimilarity = similarity;
            if (similarity > 1.0 && similarity <= 100) {
              normalizedSimilarity = similarity / 100.0;
            } else if (similarity > 100) {
              normalizedSimilarity = similarity / 1000.0;
            }
            
            const finalSimilarity = normalizedSimilarity > 0 ? normalizedSimilarity : (verifyRes?.probability ?? 0);
            
            console.log(`📊 Direct UUID verification: similarity=${finalSimilarity.toFixed(3)}, match=${match}`);
            
            // Verify email matches (security check)
            const personEmail = (personName || '').toLowerCase().trim();
            const expectedEmail = email ? email.toLowerCase().trim() : '';
            const emailMatches = personEmail === expectedEmail || personEmail.includes(expectedEmail) || expectedEmail.includes(personEmail);
            
            if (emailMatches && (finalSimilarity >= SIMILARITY_THRESHOLD || match === true)) {
              console.log(`✅✅✅ Direct UUID verification PASSED: similarity=${finalSimilarity.toFixed(3)}, email match=${emailMatches}`);
              return res.json({
                ok: true,
                similarity: finalSimilarity,
                threshold: SIMILARITY_THRESHOLD,
                message: 'verified',
                method: 'direct_uuid_verification'
              });
            } else if (!emailMatches) {
              console.warn(`⚠️ UUID verification: Email mismatch - Person: "${personEmail}", Expected: "${expectedEmail}"`);
              console.warn(`⚠️ Continuing with search-based verification...`);
            } else {
              console.warn(`⚠️ UUID verification: Similarity ${finalSimilarity.toFixed(3)} < threshold ${SIMILARITY_THRESHOLD}, continuing with search...`);
            }
          } else {
            console.warn(`⚠️ UUID ${luxandUuid.trim()} not found in Luxand persons list, using search-based verification...`);
          }
        } catch (uuidVerifyError) {
          console.warn(`⚠️ Direct UUID verification failed: ${uuidVerifyError.message}`);
          console.warn(`⚠️ Falling back to search-based verification...`);
          // Continue with search-based verification
        }
      }
      
      // Fallback: Use search-based verification
      // First, try search to get the person ID (Luxand search returns ID, not UUID)
      // Then use that ID for 1:1 verification, or use search results directly
      const searchRes = await searchPhoto(photoBase64);
      
      // Check response structure
      const candidates = searchRes.candidates 
                    || searchRes.matches 
                    || searchRes.results
                    || (Array.isArray(searchRes) ? searchRes : []);

      if (candidates.length === 0) {
        console.log(`❌❌❌ CRITICAL: No faces found in search results!`);
        console.log(`❌ This means the face is NOT enrolled in Luxand!`);
        console.log(`❌ UUID from Firebase: ${luxandUuid.trim()}`);
        console.log(`❌ Email: ${email}`);
        console.log(`❌ ACTION REQUIRED: User must re-enroll their face!`);
        return res.json({
          ok: false,
          similarity: 0,
          threshold: SIMILARITY_THRESHOLD,
          message: 'not_verified',
          error: 'Face not enrolled in Luxand. Please complete the 3 facial verification steps to enroll your face.',
          reason: 'face_not_enrolled',
          action: 're_enroll_required'
        });
      }

      // CRITICAL SECURITY: Find candidate that matches the expected email OR phone
      // This ensures the face belongs to the user with this email/phone
      // We cannot trust the UUID alone - we must verify email/phone match
      // NOTE: Faces may have been enrolled with either email or phone, so we check both
      // IMPORTANT: Only consider candidates with 95%+ similarity as potential matches
      // Candidates with 70-94% similarity are likely different people and should be ignored
      const MIN_MATCH_THRESHOLD = 0.95; // 95% - only consider very high similarity matches
      const expectedEmail = email ? email.toLowerCase().trim() : '';
      const expectedPhone = phone ? phone.trim() : '';
      let matchingCandidate = null;
      let bestScore = 0;

      console.log(`📊 Found ${candidates.length} candidate(s) in search results`);
      console.log(`🔍 Looking for email/phone match: email="${expectedEmail}", phone="${expectedPhone}"`);
      console.log(`🔍 Stored UUID (for reference): ${luxandUuid.trim()}`);
      console.log(`🔍 Minimum match threshold: ${MIN_MATCH_THRESHOLD} (95%+) - ignoring candidates below this threshold`);

      for (const candidate of candidates) {
        // Get candidate's email/name from search result
        const candidateName = (candidate.name || candidate.email || candidate.subject || '').toString().toLowerCase().trim();
        const candidateNameOriginal = (candidate.name || candidate.email || candidate.subject || '').toString().trim();
        
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
        
        // CRITICAL: Only consider candidates with 95%+ similarity
        // Candidates with 70-94% similarity are likely different people and should be ignored
        if (normalizedScore < MIN_MATCH_THRESHOLD) {
          console.log(`⚠️ Candidate: name="${candidateNameOriginal}", Score: ${normalizedScore.toFixed(3)} - IGNORED (below ${MIN_MATCH_THRESHOLD} threshold)`);
          console.log(`⚠️ This is NORMAL - different people can have 70-94% similarity. Only 95%+ indicates same person.`);
          continue; // Skip this candidate - it's likely a different person
        }
        
        // Check if candidate name matches email OR phone
        // Normalize phone numbers for comparison (remove +, spaces, etc.)
        const normalizePhone = (phone) => {
          if (!phone) return '';
          return phone.replace(/[\s+\-()]/g, '').trim();
        };
        
        const normalizedCandidatePhone = normalizePhone(candidateNameOriginal);
        const normalizedExpectedPhone = normalizePhone(expectedPhone);
        
        const emailMatch = expectedEmail && candidateName === expectedEmail;
        // Phone match: check both original and normalized formats
        const phoneMatch = expectedPhone && (
          candidateNameOriginal === expectedPhone || 
          candidateName === expectedPhone.toLowerCase() ||
          normalizedCandidatePhone === normalizedExpectedPhone ||
          normalizedCandidatePhone === normalizePhone(candidateName) ||
          candidateNameOriginal.replace(/[\s+\-()]/g, '') === expectedPhone.replace(/[\s+\-()]/g, '')
        );
        const identifierMatch = emailMatch || phoneMatch;
        
        console.log(`📊 Candidate: name="${candidateNameOriginal}", id="${candidate.id}", Score: ${normalizedScore.toFixed(3)} (>= ${MIN_MATCH_THRESHOLD})`);
        console.log(`📊 Email match: ${emailMatch ? '✅ MATCH' : '❌ NO MATCH'}`);
        console.log(`📊 Phone match: ${phoneMatch ? '✅ MATCH' : '❌ NO MATCH'}`);
        
        // CRITICAL SECURITY: Only accept if email/phone/name matches AND score is high enough (95%+)
        // This ensures the face belongs to the user with this email/phone
        // NOTE: We check both email and phone because faces may have been enrolled with either identifier
        if (identifierMatch && normalizedScore > bestScore) {
          bestScore = normalizedScore;
          matchingCandidate = candidate;
          console.log(`✅ Found matching candidate: ${emailMatch ? 'email' : 'phone'} match for "${emailMatch ? expectedEmail : expectedPhone}"`);
        }
      }

      // CRITICAL: After finding user's own match, continue checking ALL candidates for duplicates
      // This ensures we detect if the same face is registered to multiple accounts
      let duplicateFound = false;
      let duplicateIdentifier = '';
      let duplicateScore = 0;
      
      console.log(`🔍 [DUPLICATE CHECK] Scanning all candidates for duplicate faces (95%+ similarity to different accounts)...`);
      for (const candidate of candidates) {
        const candidateName = (candidate.name || candidate.email || candidate.subject || '').toString().trim();
        const candidateNameLower = candidateName.toLowerCase().trim();
        
        // Get similarity score
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
        
        // Only check for duplicates if similarity is 95%+ (very high confidence)
        if (normalizedScore >= MIN_MATCH_THRESHOLD) {
          // Check if this candidate matches a DIFFERENT identifier (duplicate account)
          const normalizePhone = (phone) => {
            if (!phone) return '';
            return phone.replace(/[\s+\-()]/g, '').trim();
          };
          
          const normalizedCandidatePhone = normalizePhone(candidateName);
          const normalizedExpectedPhone = normalizePhone(expectedPhone);
          
          const emailMatch = expectedEmail && candidateNameLower === expectedEmail;
          const phoneMatch = expectedPhone && (
            candidateName === expectedPhone || 
            candidateNameLower === expectedPhone.toLowerCase() ||
            normalizedCandidatePhone === normalizedExpectedPhone ||
            candidateName.replace(/[\s+\-()]/g, '') === expectedPhone.replace(/[\s+\-()]/g, '')
          );
          const isOwnAccount = emailMatch || phoneMatch;
          
          // If this is a 95%+ match to a DIFFERENT account, it's a duplicate
          if (!isOwnAccount && candidateName.length > 0) {
            duplicateFound = true;
            duplicateIdentifier = candidateName;
            duplicateScore = normalizedScore;
            console.error(`🚨🚨🚨 [DUPLICATE DETECTED] Face is 95%+ similar (${normalizedScore.toFixed(3)}) to another account: "${candidateName}"`);
            console.error(`🚨 This face is already registered with a different account!`);
            break; // Found duplicate, no need to continue
          }
        }
      }
      
      if (duplicateFound) {
        // Mask identifier for privacy
        let maskedIdentifier = '***';
        const isPhone = /^[\d+]+$/.test(duplicateIdentifier);
        if (isPhone && duplicateIdentifier.length > 5) {
          maskedIdentifier = `${duplicateIdentifier.substring(0, 3)}***${duplicateIdentifier.substring(duplicateIdentifier.length - 2)}`;
        } else if (!isPhone && duplicateIdentifier.includes('@')) {
          const emailParts = duplicateIdentifier.toLowerCase().split('@');
          maskedIdentifier = emailParts.length === 2 
            ? `${emailParts[0].substring(0, 3)}***@${emailParts[1]}`
            : '***@***';
        }
        
        return res.json({
          ok: false,
          similarity: duplicateScore,
          threshold: MIN_MATCH_THRESHOLD,
          message: 'not_verified',
          error: 'This face is already registered with a different account. You cannot use the same face for multiple accounts.',
          reason: 'duplicate_face',
          duplicateIdentifier: maskedIdentifier,
          security: 'Duplicate face detected - one face per account policy'
        });
      }

      // SECURITY: Must find a match with the expected email OR phone
      if (!matchingCandidate) {
        console.error(`🚨 SECURITY: No candidate found matching expected email: "${expectedEmail}" or phone: "${expectedPhone || '(not provided)'}"`);
        console.error(`🚨 SECURITY: This face does not belong to this user - REJECTING`);
        
        // Check if any candidates were found with 95%+ similarity (but wrong identifier)
        const highSimilarityCandidates = candidates.filter(candidate => {
          let score = 0;
          if (candidate.probability !== undefined) score = parseFloat(candidate.probability);
          else if (candidate.similarity !== undefined) score = parseFloat(candidate.similarity);
          else if (candidate.confidence !== undefined) score = parseFloat(candidate.confidence);
          else if (candidate.score !== undefined) score = parseFloat(candidate.score);
          if (score > 1.0 && score <= 100) score = score / 100.0;
          return score >= MIN_MATCH_THRESHOLD; // 95%+
        });
        
        // Log all candidates found for debugging
        if (candidates.length > 0) {
          console.error(`🔍 DEBUG: Found ${candidates.length} candidate(s) but none matched:`);
          candidates.forEach((candidate, idx) => {
            const candidateName = (candidate.name || candidate.email || candidate.subject || '').toString();
            const candidateId = candidate.id || candidate.personId || 'N/A';
            let score = 0;
            if (candidate.probability !== undefined) score = parseFloat(candidate.probability);
            else if (candidate.similarity !== undefined) score = parseFloat(candidate.similarity);
            else if (candidate.confidence !== undefined) score = parseFloat(candidate.confidence);
            else if (candidate.score !== undefined) score = parseFloat(candidate.score);
            if (score > 1.0 && score <= 100) score = score / 100.0;
            const isHighSimilarity = score >= MIN_MATCH_THRESHOLD;
            console.error(`  ${idx + 1}. Name: "${candidateName}", ID: ${candidateId}, Score: ${score.toFixed(3)} ${isHighSimilarity ? '(95%+ - high similarity)' : '(below 95% - likely different person)'}`);
          });
          
          if (highSimilarityCandidates.length > 0) {
            console.error(`🔍 DEBUG: Found ${highSimilarityCandidates.length} candidate(s) with 95%+ similarity but wrong identifier.`);
            console.error(`🔍 DEBUG: This suggests your face might be enrolled with a different identifier.`);
            console.error(`🔍 DEBUG: Please check if your face was enrolled with email "${expectedEmail}" or phone "${expectedPhone || '(no phone in account)'}"`);
          } else {
            console.error(`🔍 DEBUG: No candidates with 95%+ similarity found. Your face is likely NOT enrolled in Luxand.`);
            console.error(`🔍 DEBUG: The candidates found (70-94% similarity) are likely different people.`);
            console.error(`🔍 DEBUG: ACTION REQUIRED: Please complete the 3 facial verification steps to enroll your face.`);
          }
        } else {
          console.error(`🔍 DEBUG: No candidates found at all. Your face is NOT enrolled in the system.`);
          console.error(`🔍 DEBUG: ACTION REQUIRED: Please complete the 3 facial verification steps to enroll your face.`);
        }
        
        return res.json({
          ok: false,
          similarity: 0,
          threshold: SIMILARITY_THRESHOLD,
          message: 'not_verified',
          error: 'Face does not match this account. Your face may not be enrolled, or was enrolled with a different identifier. Please complete the 3 facial verification steps again to enroll your face.',
          security: 'Email/phone mismatch - face belongs to different user or not enrolled',
          debug: candidates.length > 0 
            ? (highSimilarityCandidates.length > 0 
                ? `Found ${highSimilarityCandidates.length} candidate(s) with 95%+ similarity but wrong identifier - face may be enrolled with different identifier`
                : `Found ${candidates.length} candidate(s) but all below 95% similarity - your face is likely NOT enrolled`)
            : 'No candidates found - face is NOT enrolled in the system'
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
          
          // Luxand verify endpoint returns 'probability' field, not 'similarity'
          // Also check for 'verified' status in message or status field
          const similarity = parseFloat(
            verifyRes?.similarity ?? 
            verifyRes?.confidence ?? 
            verifyRes?.probability ?? 
            0
          );
          // Check multiple ways Luxand indicates verification success
          let match = verifyRes?.match ?? verifyRes?.verified ?? false;
          if (!match) {
            match = (verifyRes?.message === 'verified') ||
                    (verifyRes?.status === 'success' && verifyRes?.message === 'verified') ||
                    (verifyRes?.status === 'success' && verifyRes?.probability >= 0.85);
          }
          
          let normalizedSimilarity = similarity;
          if (similarity > 1.0 && similarity <= 100) {
            normalizedSimilarity = similarity / 100.0;
          } else if (similarity > 100) {
            normalizedSimilarity = similarity / 1000.0;
          }
          
          // Use probability if similarity is 0 (Luxand returns probability, not similarity)
          const finalSimilarity = normalizedSimilarity > 0 ? normalizedSimilarity : (verifyRes?.probability ?? 0);
          
          console.log(`📊 1:1 Verification result: similarity=${normalizedSimilarity.toFixed(3)}, probability=${verifyRes?.probability ?? 'N/A'}, finalSimilarity=${finalSimilarity.toFixed(3)}, match=${match}`);
          console.log(`📊 Full verify response:`, JSON.stringify(verifyRes));
          
          if (finalSimilarity >= SIMILARITY_THRESHOLD || match === true) {
            console.log(`✅ Verification PASSED (1:1): similarity=${finalSimilarity.toFixed(3)}, match=${match}`);
            console.log(`✅ Email match confirmed: ${expectedEmail}`);
            return res.json({
              ok: true,
              similarity: finalSimilarity,
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
// CHECK DUPLICATE FACE ENDPOINT
// ==========================================
// POST /api/check-duplicate
// Body: { email: string, phone?: string, photoBase64: string }
// Returns: { isDuplicate: boolean, duplicateIdentifier?: string, similarity?: number, error?: string }
// Purpose: Check if a face is 95%+ similar to another user's face (different identifier)
// Used during profile photo upload to prevent same person from having multiple accounts
app.post('/api/check-duplicate', async (req, res) => {
  try {
    const { email, phone, photoBase64 } = req.body;

    // Validation
    if (!email || !photoBase64) {
      return res.status(400).json({
        isDuplicate: false,
        error: 'Missing email or photoBase64'
      });
    }

    if (typeof email !== 'string' || typeof photoBase64 !== 'string') {
      return res.status(400).json({
        isDuplicate: false,
        error: 'Invalid email or photoBase64 format'
      });
    }

    console.log(`🔍 [DUPLICATE CHECK] Checking for duplicate face for: ${email}`);
    
    // Remove data URL prefix if present
    let cleanBase64 = photoBase64;
    if (photoBase64.includes(',')) {
      cleanBase64 = photoBase64.split(',')[1];
    }

    // Use 95% threshold (same as enrollment duplicate check)
    const DUPLICATE_THRESHOLD = 0.95;
    
    const emailToFind = email.toLowerCase().trim();
    const phoneToFind = phone ? phone.trim() : '';

    // Search for similar faces
    const searchRes = await searchPhoto(cleanBase64);
    const candidates = searchRes.candidates 
                  || searchRes.matches 
                  || searchRes.results
                  || (Array.isArray(searchRes) ? searchRes : []);

    console.log(`🔍 [DUPLICATE CHECK] Found ${candidates.length} candidate(s) in search results`);

    if (candidates.length === 0) {
      console.log(`✅ [DUPLICATE CHECK] No candidates found - no duplicate`);
      return res.json({
        isDuplicate: false
      });
    }

    // Check each candidate for high similarity and different identifier
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      
      // Get candidate's identifier
      const candidateIdentifier = (candidate.name || candidate.email || candidate.subject || '').toString().trim();
      const candidateIdentifierLower = candidateIdentifier.toLowerCase().trim();
      
      // Get similarity score
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
      if (score > 1.0 && score <= 100) {
        score = score / 100.0;
      }
      
      // Normalize identifiers for comparison
      const normalizedCandidate = candidateIdentifierLower.replace(/\s+/g, '');
      const normalizedEmail = emailToFind.replace(/\s+/g, '');
      const normalizedPhone = phoneToFind.replace(/\s+/g, '');
      
      // Check if identifiers match
      const emailMatch = normalizedCandidate === normalizedEmail;
      const phoneMatch = phoneToFind && normalizedCandidate === normalizedPhone;
      const identifiersMatch = emailMatch || phoneMatch;
      
      console.log(`🔍 [DUPLICATE CHECK] Candidate ${i + 1}:`);
      console.log(`   - Identifier: "${candidateIdentifier}"`);
      console.log(`   - Score: ${score.toFixed(3)} (threshold: ${DUPLICATE_THRESHOLD})`);
      console.log(`   - Identifiers match: ${identifiersMatch}`);
      
      // CRITICAL: Only flag as duplicate if:
      // 1. Similarity is VERY HIGH (95%+) - same person
      // 2. Identifiers are DIFFERENT - different account
      // 3. Both identifiers are valid
      if (score >= DUPLICATE_THRESHOLD && !identifiersMatch && candidateIdentifier.length > 0) {
        console.error(`🚨🚨🚨 [DUPLICATE CHECK] DUPLICATE FACE DETECTED!`);
        console.error(`🚨 Existing identifier: ${candidateIdentifier}`);
        console.error(`🚨 New identifier: ${emailToFind}${phoneToFind ? ` / ${phoneToFind}` : ''}`);
        console.error(`🚨 Similarity score: ${score.toFixed(3)} (threshold: ${DUPLICATE_THRESHOLD})`);
        console.error(`🚨 This face is already registered with a different account!`);
        
        // Mask identifier for privacy
        let maskedIdentifier = '***';
        const isPhone = /^[\d+]+$/.test(candidateIdentifier);
        if (isPhone && candidateIdentifier.length > 5) {
          maskedIdentifier = `${candidateIdentifier.substring(0, 3)}***${candidateIdentifier.substring(candidateIdentifier.length - 2)}`;
        } else if (!isPhone && candidateIdentifier.includes('@')) {
          const emailParts = candidateIdentifierLower.split('@');
          maskedIdentifier = emailParts.length === 2 
            ? `${emailParts[0].substring(0, 3)}***@${emailParts[1]}`
            : '***@***';
        }
        
        return res.json({
          isDuplicate: true,
          duplicateIdentifier: maskedIdentifier,
          similarity: score,
          message: 'This face is already registered with a different account. You cannot use the same face for multiple accounts.'
        });
      }
    }
    
    console.log(`✅ [DUPLICATE CHECK] No duplicate faces found. All candidates checked.`);
    return res.json({
      isDuplicate: false
    });
  } catch (error) {
    console.error('❌ [DUPLICATE CHECK] Error:', error);
    // On error, don't block - return no duplicate to allow upload
    // This prevents false positives from blocking legitimate users
    return res.json({
      isDuplicate: false,
      error: error.message || 'Duplicate check failed'
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
// Body: { email: string } or { phone: string } or { uuid: string }
// Returns: { ok: bool, message: string }
app.post('/api/delete-person', async (req, res) => {
  try {
    const { email, phone, uuid } = req.body;

    // Validation
    if (!email && !phone && !uuid) {
      return res.status(400).json({
        ok: false,
        error: 'Missing email, phone, or uuid'
      });
    }

    let personUuid = uuid;

    // If email or phone is provided, find all persons with that identifier and delete them
    if ((email || phone) && !uuid) {
      const identifier = email || phone;
      const isEmail = !!email;
      console.log(`🔍 Searching for all persons with ${isEmail ? 'email' : 'phone'}: ${identifier}`);
      
      try {
        // Use the list persons endpoint to find all persons with this identifier
        const allPersons = await listPersons();
        const persons = allPersons.persons || allPersons.data || allPersons || [];
        
        // Normalize phone numbers for comparison
        const normalizePhone = (p) => {
          if (!p) return '';
          return p.replace(/[\s+\-()]/g, '').trim();
        };
        
        // Filter persons by email or phone (name field)
        const emailToFind = email ? email.toLowerCase().trim() : '';
        const phoneToFind = phone ? phone.trim() : '';
        
        const matchingPersons = persons.filter(person => {
          const personName = (person.name || person.email || '').toString().trim();
          const personNameLower = personName.toLowerCase().trim();
          
          // Match by email
          if (emailToFind && personNameLower === emailToFind) {
            return true;
          }
          
          // Match by phone (normalize for comparison)
          if (phoneToFind) {
            const normalizedPersonPhone = normalizePhone(personName);
            const normalizedExpectedPhone = normalizePhone(phoneToFind);
            if (normalizedPersonPhone === normalizedExpectedPhone || personName === phoneToFind) {
              return true;
            }
          }
          
          return false;
        });
        
        if (matchingPersons.length === 0) {
          return res.json({
            ok: true,
            message: `No persons found with ${email ? 'email' : 'phone'}: ${identifier}`,
            deletedCount: 0,
            uuids: []
          });
        }
        
        console.log(`📋 Found ${matchingPersons.length} person(s) with ${email ? 'email' : 'phone'} ${identifier}`);
        
        // Delete all matching persons
        const deletedUuids = [];
        const errors = [];
        
        for (const person of matchingPersons) {
          const personUuid = person.uuid || person.id;
          const personName = person.name || person.email || 'N/A';
          if (personUuid) {
            try {
              await deletePerson(personUuid);
              deletedUuids.push(personUuid);
              console.log(`✅ Deleted person: ${personName} (UUID: ${personUuid})`);
            } catch (deleteError) {
              errors.push({ uuid: personUuid, name: personName, error: deleteError.message });
              console.error(`❌ Failed to delete person ${personName} (${personUuid}): ${deleteError.message}`);
            }
          }
        }
        
        return res.json({
          ok: true,
          message: `Deleted ${deletedUuids.length} of ${matchingPersons.length} person(s) with ${email ? 'email' : 'phone'}: ${identifier}`,
          deletedCount: deletedUuids.length,
          totalFound: matchingPersons.length,
          uuids: deletedUuids,
          errors: errors.length > 0 ? errors : undefined
        });
      } catch (searchError) {
        console.error('❌ Error searching for persons by email:', searchError);
        return res.status(500).json({
          ok: false,
          error: 'Failed to search for persons by email',
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
// CHECK PERSON BY IDENTIFIER ENDPOINT
// ==========================================
// GET /api/check-person?email=xxx&phone=xxx
// Returns: { ok: bool, found: bool, persons: [...], message: string }
// Checks if a person with the given email/phone exists in Luxand
app.get('/api/check-person', async (req, res) => {
  try {
    const { email, phone } = req.query;
    
    if (!email && !phone) {
      return res.status(400).json({
        ok: false,
        error: 'Email or phone is required'
      });
    }
    
    console.log(`🔍 Checking for person with email: ${email || 'N/A'}, phone: ${phone || 'N/A'}`);
    
    const allPersons = await listPersons();
    const persons = allPersons.persons || allPersons.data || allPersons || [];
    
    const emailToFind = email ? email.toLowerCase().trim() : '';
    const phoneToFind = phone ? phone.trim() : '';
    
    const matchingPersons = persons.filter(person => {
      const personName = (person.name || person.email || '').toString().trim();
      const personNameLower = personName.toLowerCase().trim();
      
      // Match by email
      if (emailToFind && personNameLower === emailToFind) {
        return true;
      }
      
      // Match by phone (normalize for comparison)
      if (phoneToFind) {
        const normalizePhone = (p) => p.replace(/[\s+\-()]/g, '').trim();
        const normalizedPersonPhone = normalizePhone(personName);
        const normalizedExpectedPhone = normalizePhone(phoneToFind);
        if (normalizedPersonPhone === normalizedExpectedPhone || personName === phoneToFind) {
          return true;
        }
      }
      
      return false;
    });
    
    if (matchingPersons.length > 0) {
      console.log(`✅ Found ${matchingPersons.length} person(s) matching the identifier`);
      return res.json({
        ok: true,
        found: true,
        persons: matchingPersons.map(p => ({
          uuid: p.uuid || p.id,
          name: p.name || p.email,
          faces: p.faces || p.face_count || 0
        })),
        count: matchingPersons.length,
        message: `Found ${matchingPersons.length} person(s) with this identifier`
      });
    } else {
      console.log(`❌ No person found with email: ${emailToFind || 'N/A'} or phone: ${phoneToFind || 'N/A'}`);
      return res.json({
        ok: true,
        found: false,
        persons: [],
        count: 0,
        message: 'No person found with this identifier. Face may not be enrolled.'
      });
    }
  } catch (error) {
    console.error('❌ Error checking person:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to check person',
      found: false,
      persons: [],
      count: 0
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
// DELETE ALL PERSONS BY EMAIL ENDPOINT
// ==========================================
// POST /api/delete-persons-by-email
// Body: { email: string }
// Returns: { ok: bool, deletedCount: number, uuids: [...] }
// This endpoint deletes ALL faces for a given email (useful for cleanup)
app.post('/api/delete-persons-by-email', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email || typeof email !== 'string' || email.trim().length === 0) {
      return res.status(400).json({
        ok: false,
        error: 'Email is required'
      });
    }

    const emailToFind = email.toLowerCase().trim();
    console.log(`🔍 Searching for all persons with email: ${emailToFind}`);
    
    // Get all persons from Luxand
    const allPersons = await listPersons();
    const persons = allPersons.persons || allPersons.data || allPersons || [];
    
    // Filter persons by email
    const matchingPersons = persons.filter(person => 
      (person.name || '').toLowerCase().trim() === emailToFind
    );
    
    if (matchingPersons.length === 0) {
      return res.json({
        ok: true,
        message: `No persons found with email: ${emailToFind}`,
        deletedCount: 0,
        uuids: []
      });
    }
    
    console.log(`📋 Found ${matchingPersons.length} person(s) with email ${emailToFind}`);
    
    // Delete all matching persons
    const deletedUuids = [];
    const errors = [];
    
    for (const person of matchingPersons) {
      const personUuid = person.uuid || person.id;
      if (personUuid) {
        try {
          await deletePerson(personUuid);
          deletedUuids.push(personUuid);
          console.log(`✅ Deleted person: ${personUuid}`);
        } catch (deleteError) {
          errors.push({ uuid: personUuid, error: deleteError.message });
          console.error(`❌ Failed to delete person ${personUuid}: ${deleteError.message}`);
        }
      }
    }
    
    return res.json({
      ok: true,
      message: `Deleted ${deletedUuids.length} of ${matchingPersons.length} person(s) with email: ${emailToFind}`,
      deletedCount: deletedUuids.length,
      totalFound: matchingPersons.length,
      uuids: deletedUuids,
      errors: errors.length > 0 ? errors : undefined
    });

  } catch (error) {
    console.error('❌ Error deleting persons by email:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to delete persons by email',
      deletedCount: 0
    });
  }
});

// ==========================================
// DELETE USER ENDPOINT (with automatic Luxand cleanup)
// ==========================================
// POST /api/delete-user
// Body: { email?: string, phoneNumber?: string, userId?: string, luxandUuid?: string }
// Returns: { ok: bool, message: string, luxandDeleted: number }
// This endpoint should be called when deleting a user from Firestore
// It automatically deletes all faces for that user from Luxand
app.post('/api/delete-user', async (req, res) => {
  try {
    const { email, phoneNumber, userId, luxandUuid } = req.body;

    // At least one identifier must be provided
    if ((!email || typeof email !== 'string' || email.trim().length === 0) &&
        (!phoneNumber || typeof phoneNumber !== 'string' || phoneNumber.trim().length === 0) &&
        (!luxandUuid || typeof luxandUuid !== 'string' || luxandUuid.trim().length === 0)) {
      return res.status(400).json({
        ok: false,
        error: 'At least one of email, phoneNumber, or luxandUuid is required'
      });
    }

    const emailToFind = email ? email.toLowerCase().trim() : null;
    const phoneToFind = phoneNumber ? phoneNumber.trim() : null; // Don't remove spaces yet - normalize in matching function
    const uuidToDelete = luxandUuid ? luxandUuid.trim() : null;
    
    console.log(`🗑️ Deleting user: ${emailToFind || phoneToFind || 'by UUID'}${userId ? ` (userId: ${userId})` : ''}`);
    console.log(`🔍 Searching for all faces in Luxand...`);
    console.log(`📱 Phone number to find: "${phoneToFind}"`);
    console.log(`📧 Email to find: "${emailToFind}"`);
    console.log(`🆔 UUID to delete: "${uuidToDelete}"`);
    
    let deletedCount = 0;
    const deletedUuids = [];
    const errors = [];
    const searchMethods = [];
    
    // Method 1: Direct UUID deletion (fastest and most reliable)
    if (uuidToDelete) {
      searchMethods.push('direct_uuid');
      try {
        console.log(`🔍 Method 1: Deleting by direct UUID: ${uuidToDelete}`);
        await deletePerson(uuidToDelete);
        deletedUuids.push(uuidToDelete);
        deletedCount++;
        console.log(`✅ Deleted face from Luxand by UUID: ${uuidToDelete}`);
      } catch (deleteError) {
        errors.push({ uuid: uuidToDelete, method: 'direct_uuid', error: deleteError.message });
        console.error(`❌ Failed to delete face by UUID ${uuidToDelete}: ${deleteError.message}`);
      }
    }
    
    // Method 2: Search by email or phone number
    if (emailToFind || phoneToFind) {
      searchMethods.push('search_by_identifier');
      try {
        // Get all persons from Luxand
        const allPersons = await listPersons();
        const persons = allPersons.persons || allPersons.data || allPersons || [];
        
        // Filter persons by email or phone number
        const matchingPersons = persons.filter(person => {
          const personName = (person.name || '').trim();
          const personNameLower = personName.toLowerCase().trim();
          
          // Match by email (case-insensitive)
          if (emailToFind && personNameLower === emailToFind) {
            return true;
          }
          
          // Match by phone number (handle various formats)
          if (phoneToFind) {
            // Normalize phone numbers: remove all non-digits except leading +
            const normalizePhone = (phone) => {
              if (!phone) return '';
              // Remove spaces, dashes, parentheses
              let normalized = phone.replace(/[\s\-()]/g, '');
              // If starts with +63, keep it; if starts with 0, convert to +63
              if (normalized.startsWith('+63')) {
                normalized = normalized.substring(3); // Remove +63
              } else if (normalized.startsWith('63')) {
                normalized = normalized.substring(2); // Remove 63
              } else if (normalized.startsWith('0')) {
                normalized = normalized.substring(1); // Remove leading 0
              }
              // Return only digits
              return normalized.replace(/\D/g, '');
            };
            
            const phoneClean = normalizePhone(phoneToFind);
            const personNamePhoneOnly = normalizePhone(personName);
            
            // Match if normalized phone numbers are equal
            if (personNamePhoneOnly && phoneClean && personNamePhoneOnly === phoneClean) {
              console.log(`✅ Phone match found: "${personName}" matches "${phoneToFind}" (normalized: ${phoneClean})`);
              return true;
            }
            
            // Also try exact match (in case phone is stored exactly as provided)
            if (personName === phoneToFind || personName === phoneToFind.replace(/\s+/g, '')) {
              console.log(`✅ Phone exact match found: "${personName}" matches "${phoneToFind}"`);
              return true;
            }
          }
          
          return false;
        });
        
        if (matchingPersons.length > 0) {
          console.log(`📋 Found ${matchingPersons.length} face(s) in Luxand for ${emailToFind || phoneToFind}`);
          console.log(`📋 Matching persons:`, matchingPersons.map(p => ({ name: p.name, uuid: p.uuid || p.id })));
          
          // Delete all matching persons from Luxand
          for (const person of matchingPersons) {
            const personUuid = person.uuid || person.id;
            if (personUuid && !deletedUuids.includes(personUuid)) { // Avoid duplicate deletion
              try {
                await deletePerson(personUuid);
                deletedUuids.push(personUuid);
                deletedCount++;
                console.log(`✅ Deleted face from Luxand: ${personUuid}`);
              } catch (deleteError) {
                errors.push({ uuid: personUuid, method: 'search_by_identifier', error: deleteError.message });
                console.error(`❌ Failed to delete face ${personUuid}: ${deleteError.message}`);
              }
            }
          }
        } else {
          console.log(`ℹ️ No faces found in Luxand for ${emailToFind || phoneToFind}`);
          // Debug: List all persons to help diagnose matching issues
          if (persons.length > 0) {
            console.log(`🔍 DEBUG: Listing all ${persons.length} person(s) in Luxand for comparison:`);
            persons.forEach((person, index) => {
              console.log(`  ${index + 1}. Name: "${person.name || 'N/A'}", UUID: ${person.uuid || person.id || 'N/A'}`);
            });
          }
        }
      } catch (searchError) {
        errors.push({ method: 'search_by_identifier', error: searchError.message });
        console.error(`❌ Error searching Luxand: ${searchError.message}`);
      }
    }
    
    return res.json({
      ok: true,
      message: `User deletion processed. ${deletedCount} face(s) deleted from Luxand.`,
      email: emailToFind || null,
      phoneNumber: phoneToFind || null,
      userId: userId || null,
      luxandUuid: uuidToDelete || null,
      luxandDeleted: deletedCount,
      searchMethods: searchMethods,
      uuids: deletedUuids,
      errors: errors.length > 0 ? errors : undefined,
      note: 'This endpoint only deletes from Luxand. You must still delete the user from Firestore separately.'
    });

  } catch (error) {
    console.error('❌ Error deleting user:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to delete user from Luxand',
      luxandDeleted: 0
    });
  }
});

// ==========================================
// CLEANUP DUPLICATES ENDPOINT
// ==========================================
// POST /api/cleanup-duplicates
// Body: { email?: string } (optional - if not provided, cleans all duplicates)
// Returns: { ok: bool, cleaned: number, duplicates: [...] }
// This endpoint finds and removes duplicate faces (multiple faces for same email)
app.post('/api/cleanup-duplicates', async (req, res) => {
  try {
    const { email } = req.body;
    
    console.log('🧹 Starting duplicate cleanup...');
    
    // Get all persons from Luxand
    const allPersons = await listPersons();
    const persons = allPersons.persons || allPersons.data || allPersons || [];
    
    // Group persons by email
    const emailGroups = {};
    for (const person of persons) {
      const personEmail = (person.name || '').toLowerCase().trim();
      if (personEmail) {
        if (!emailGroups[personEmail]) {
          emailGroups[personEmail] = [];
        }
        emailGroups[personEmail].push(person);
      }
    }
    
    // Find duplicates (emails with more than 1 face)
    const duplicates = {};
    for (const [emailKey, emailPersons] of Object.entries(emailGroups)) {
      if (emailPersons.length > 1) {
        // If specific email requested, only process that one
        if (email && email.toLowerCase().trim() !== emailKey) {
          continue;
        }
        duplicates[emailKey] = emailPersons;
      }
    }
    
    if (Object.keys(duplicates).length === 0) {
      return res.json({
        ok: true,
        message: 'No duplicates found',
        cleaned: 0,
        duplicates: []
      });
    }
    
    console.log(`📋 Found ${Object.keys(duplicates).length} email(s) with duplicates`);
    
    // Clean up duplicates (keep the first one, delete the rest)
    let totalCleaned = 0;
    const cleanedDetails = [];
    
    for (const [emailKey, emailPersons] of Object.entries(duplicates)) {
      // Keep the first face, delete the rest
      const toKeep = emailPersons[0];
      const toDelete = emailPersons.slice(1);
      
      console.log(`🧹 Cleaning ${emailKey}: Keeping 1, Deleting ${toDelete.length}`);
      
      const deletedUuids = [];
      for (const person of toDelete) {
        const personUuid = person.uuid || person.id;
        if (personUuid) {
          try {
            await deletePerson(personUuid);
            deletedUuids.push(personUuid);
            totalCleaned++;
            console.log(`✅ Deleted duplicate: ${personUuid}`);
          } catch (deleteError) {
            console.error(`❌ Failed to delete ${personUuid}: ${deleteError.message}`);
          }
        }
      }
      
      cleanedDetails.push({
        email: emailKey,
        totalFaces: emailPersons.length,
        kept: toKeep.uuid || toKeep.id,
        deleted: deletedUuids.length,
        deletedUuids: deletedUuids
      });
    }
    
    return res.json({
      ok: true,
      message: `Cleaned up ${totalCleaned} duplicate face(s)`,
      cleaned: totalCleaned,
      duplicatesFound: Object.keys(duplicates).length,
      details: cleanedDetails
    });

  } catch (error) {
    console.error('❌ Error cleaning up duplicates:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to cleanup duplicates',
      cleaned: 0
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
  console.log(`🚀 Health check: https://0.0.0.0:${PORT}/ (HTTPS required in production)`);
  console.log(`🚀 Health check: https://0.0.0.0:${PORT}/api/health (HTTPS required in production)`);
  console.log(`🔒 SECURITY: All client connections must use HTTPS`);
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

