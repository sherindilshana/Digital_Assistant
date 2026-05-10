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
class FormAssistView(APIView):
    def post(self, request):
        field_hint = request.data.get('field_hint', '')
        
        if not field_hint:
            return Response({"error": "No field_hint provided"}, status=status.HTTP_400_BAD_REQUEST)

        print(f"Form Field Detected: {field_hint}") 

        # Get the action and Malayalam audio from Gemini
        action_data = GeminiService.get_form_action(field_hint)
        
        # Return the JSON back to Flutter!
        return Response(action_data, status=status.HTTP_200_OK)
class UniversalScanView(APIView):
    def post(self, request):
        raw_text = request.data.get('raw_text', '')
        # This calls the method you just perfected
        extracted_map = GeminiService.extract_universal_id_data(raw_text)
        return Response({"data_map": extracted_map}, status=status.HTTP_200_OK)

class VoiceFormatView(APIView):
    def post(self, request):
        raw_audio = request.data.get('raw_audio', '')
        formatted_text = GeminiService.format_voice_input(raw_audio)
        return Response({"formatted_text": formatted_text}, status=status.HTTP_200_OK)