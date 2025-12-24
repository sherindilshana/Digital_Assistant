import google.generativeai as genai
from django.conf import settings

# Configure using the key from settings.py
genai.configure(api_key=settings.GEMINI_API_KEY)

class GeminiService:
    @staticmethod
    def get_natural_translation(text):
        """
        Sends text to Gemini and asks for a natural, elderly-friendly translation.
        """
        try:
            model = genai.GenerativeModel('gemini-2.5-flash')
            
            prompt = f"""
            Act as a helpful assistant for an elderly person in Kerala.
            Translate the following English text into natural, spoken Malayalam.
            
            Rules:
            1. Simplify complex logic (e.g., "A caused B" -> "A happened. B happened").
            2. Use respectful, warm tone.
            3. Avoid complex Sanskrit words; use daily-life Malayalam.
            4. If the text is technical (like "Virtualization"), explain it simply in Malayalam.

            Input Text: "{text}"
            Malayalam Translation:
            """
            
            response = model.generate_content(prompt)
            return response.text.strip()
            
        except Exception as e:
            print(f"Gemini Error: {e}")
            return None  # Return None so we know it failed