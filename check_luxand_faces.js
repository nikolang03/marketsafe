// Script to check Luxand faces and identify duplicates/orphaned faces
import fetch from 'node-fetch';

const BACKEND_URL = 'https://marketsafe-production.up.railway.app';

async function checkLuxandFaces() {
  try {
    console.log('🔍 Fetching all faces from Luxand...\n');
    
    const response = await fetch(`${BACKEND_URL}/api/list-persons`);
    const data = await response.json();
    
    if (!data.ok) {
      console.error('❌ Error:', data.error);
      return;
    }
    
    const persons = data.persons || [];
    console.log(`📋 Found ${persons.length} face(s) in Luxand:\n`);
    
    // Group by email/phone to find duplicates
    const emailGroups = {};
    persons.forEach(person => {
      const identifier = person.name || 'Unknown';
      if (!emailGroups[identifier]) {
        emailGroups[identifier] = [];
      }
      emailGroups[identifier].push(person);
    });
    
    // Display all faces
    persons.forEach((person, index) => {
      const identifier = person.name || 'Unknown';
      const uuid = person.uuid || 'N/A';
      const faceCount = person.face?.length || 0;
      console.log(`${index + 1}. ${identifier}`);
      console.log(`   UUID: ${uuid}`);
      console.log(`   Faces: ${faceCount}`);
      console.log('');
    });
    
    // Find duplicates
    console.log('🔍 Checking for duplicates...\n');
    const duplicates = Object.entries(emailGroups).filter(([email, persons]) => persons.length > 1);
    
    if (duplicates.length > 0) {
      console.log('⚠️ DUPLICATES FOUND:\n');
      duplicates.forEach(([email, persons]) => {
        console.log(`   ${email}: ${persons.length} face(s)`);
        persons.forEach((person, idx) => {
          console.log(`     ${idx + 1}. UUID: ${person.uuid}`);
        });
        console.log('');
      });
    } else {
      console.log('✅ No duplicates found (each email has only 1 face)\n');
    }
    
    // Summary
    console.log('📊 SUMMARY:');
    console.log(`   Total faces in Luxand: ${persons.length}`);
    console.log(`   Unique emails/phones: ${Object.keys(emailGroups).length}`);
    if (duplicates.length > 0) {
      console.log(`   Emails with duplicates: ${duplicates.length}`);
      const totalDuplicateFaces = duplicates.reduce((sum, [_, persons]) => sum + persons.length, 0);
      console.log(`   Total duplicate faces: ${totalDuplicateFaces}`);
    }
    
    console.log('\n💡 To clean up duplicates, use:');
    console.log(`   POST ${BACKEND_URL}/api/cleanup-duplicates`);
    console.log('   Body: { "email": "email@example.com" } (optional - cleans all if omitted)');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

checkLuxandFaces();

