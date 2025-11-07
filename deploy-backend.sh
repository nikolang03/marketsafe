#!/bin/bash
# Backend Deployment Script for Railway
# This script helps you deploy your backend to Railway

echo "🚀 MarketSafe Backend Deployment Helper"
echo "========================================"
echo ""
echo "This script will help you deploy your backend to Railway."
echo ""
echo "Prerequisites:"
echo "1. Railway account (https://railway.app)"
echo "2. GitHub account with your code"
echo ""
echo "Steps:"
echo "1. Go to https://railway.app"
echo "2. Sign up/Login with GitHub"
echo "3. Click 'New Project' → 'Deploy from GitHub repo'"
echo "4. Select your repository"
echo "5. Add these environment variables:"
echo "   - LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1"
echo "   - PORT=4000"
echo "   - ALLOWED_ORIGINS=*"
echo "6. Railway will deploy automatically"
echo "7. Copy the URL (e.g., https://your-app.up.railway.app)"
echo ""
echo "After deployment, update the backend URL in:"
echo "  lib/services/production_face_recognition_service.dart"
echo ""

