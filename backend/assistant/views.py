from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from .services import GeminiService
from .offline_services import OfflineService 

class TranslationView(APIView):
    def post(self, request):
        text = request.data.get('text', '')
        
        if not text:
            return Response({"error": "No text provided"}, status=status.HTTP_400_BAD_REQUEST)

        print(f"Request: {text[:30]}...") 

        # Initialize variables
        translation = None
        source = "unknown"

        # --- STRATEGY: HYBRID FALLBACK ---

        # 1. Try Online (Gemini)
        try:
            print("Attempting Online Translation...")
            
            # 👇 UNCOMMENT THIS LINE TO FORCE OFFLINE MODE (For Demo/Testing)
            # raise Exception("Forcing Offline Mode for Testing") 

            translation = GeminiService.get_natural_translation(text)
            
            if translation:
                source = "gemini-cloud"
        
        except Exception as e:
            print(f"⚠️ Online Mode Failed: {e}")
            # We catch the error so the code continues to the next step!
            translation = None

        # 2. If Online Failed (or returned None), Use Offline (NLLB)
        if not translation:
            print("Switching to Offline NLLB Model...")
            try:
                translation = OfflineService.get_translation(text)
                source = "offline-nllb-model"
            except Exception as e:
                print(f"❌ Offline Mode Failed: {e}")

        # 3. Final Response
        if translation:
            return Response({
                "original": text,
                "translated": translation,
                "source": source 
            }, status=status.HTTP_200_OK)
        else:
            return Response({
                "error": "Both online and offline translation failed."
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)