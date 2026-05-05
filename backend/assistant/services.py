import google.generativeai as genai
from django.conf import settings
import json 
import requests
import re
SAFE_BROWSING_API_KEY ="AIzaSyCWjlHWvWd8n69yNnq0zbG1REyYT6FedsE"
def extract_urls(text):
    pattern = r'(https?://[^\s]+)'
    return re.findall(pattern, text)
def check_url_safety(url):
    endpoint = f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={SAFE_BROWSING_API_KEY}"
    body = {
        "client": {
            "clientId": "orukoottu",
            "clientVersion": "1.0"
        },
        "threatInfo": {
            "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING"],
            "platformTypes": ["ANY_PLATFORM"],
            "threatEntryTypes": ["URL"],
            "threatEntries": [{"url": url}]
        }
    }
    response = requests.post(endpoint, json=body)    
    result = response.json()
    if "matches" in result:
        return "⚠️ Unsafe website detected"
    else:
        return "✅ Safe source" 
# Configure using the key from settings.py
#genai.configure(api_key=settings.GEMINI_API_KEY)
NEW_KEY = "AIzaSyCR6psw3SapqdMH9viyr9ZbCtq7YKedQY8"
genai.configure(api_key=NEW_KEY)

class GeminiService:
    # --- EXISTING: THE TRANSLATION BRAIN ---
    @staticmethod
    def get_natural_translation(text):
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
            return None  

    # --- NEW: THE FORM ASSISTANT BRAIN ---
    @staticmethod
    def get_form_action(field_hint):
        try:
            model = genai.GenerativeModel('gemini-2.5-flash')
            
            prompt = f"""
            You are a form assistant for elderly Malayalam speakers.
            The user is looking at a form field labeled: "{field_hint}"
            
            CRITICAL RULES for choosing the action:
            1. CAMERA: MUST use for Name (e.g., "Full Name", "First Name", "Last Name"), ID cards, Aadhaar, PAN, Bank Passbook, Address, Bills.
            2. VOICE: MUST use ONLY for numbers or dynamic text (Age, Mobile Number, Pincode, Dates, Amounts, Cities).
            3. EMAIL_POPUP: MUST use for Email IDs.
            4. AUTO_WAIT: MUST use for OTP / One-Time Passwords.
               -> If AUTO_WAIT, 'malayalam_audio' MUST be EXACTLY: "മെസ്സേജ് വരാൻ കാത്തിരിക്കുന്നു. ഞാൻ തനിയെ പൂരിപ്പിക്കാം."
            5. GUIDE_KEYBOARD: MUST use for Passwords, MPINs, Secret Codes.
               -> If GUIDE_KEYBOARD, 'malayalam_audio' MUST be EXACTLY: "ഇവിടെ പാസ്‌വേഡ് ആണ് വേണ്ടത്. ഗൂഗിൾ പാസ്‌വേഡ് മാനേജറിൽ സേവ് ചെയ്തിട്ടുണ്ടെങ്കിൽ അത് തനിയെ പൂരിപ്പിക്കും. അല്ലെങ്കിൽ നിങ്ങൾക്ക് ടൈപ്പ് ചെയ്യാം, അല്ലെങ്കിൽ ഈ ബട്ടണിൽ തൊട്ട് പറയാവുന്നതാണ്. ഇതൊന്നും സാധ്യമല്ലെങ്കിൽ, താഴെയുള്ള ഫോർഗോട്ട് പാസ്‌വേഡ് എടുക്കുക."
            
            Respond ONLY with a valid JSON dictionary:
            {{
                "action": "THE_ACTION_CHOSEN",
                "malayalam_audio": "The corresponding Malayalam instruction."
            }}
            """
            
            response = model.generate_content(prompt)
            response_text = response.text.strip()
            
            if response_text.startswith('```json'):
                response_text = response_text[7:-3]
            elif response_text.startswith('```'):
                response_text = response_text[3:-3]
                
            return json.loads(response_text)
            
        except Exception as e:
            print(f"Gemini Form Error: {e}")
            return {"action": "VOICE", "malayalam_audio": "ദയവായി വിവരങ്ങൾ പറയുക."}
    @staticmethod
    def extract_universal_id_data(raw_text):
        try:
            model = genai.GenerativeModel('gemini-2.5-flash')
            prompt = f"""
            You are an expert data extractor for Indian documents (ID Cards, Passbooks, Bills).
            Scanned Text: "{raw_text}"

            TASK:
            Extract every detail into a JSON dictionary using these EXACT keys:
            "full name", "dob", "gender", "id number", "ifsc", "account number", "consumer number",
            "branch name", "full address", "house name", "street", "place", "district", "state", "pincode".

            RULES:
            1. NAME: Extract the person's full name exactly. Remove titles like "Mr." or "Smt.".
            2. BANK & UTILITY: For "account number", "consumer number", and "id number", extract ONLY digits.
            3. IFSC: Extract exactly the 11-character alphanumeric code.
            4. BRANCH: Explicitly lookfor the name of the bank branch location.
            5. ADDRESS (FULL): The complete address exactly as it appears.
            6. ADDRESS (SPLIT): Break it down into "house name", "street", "place", "district", "state".
            7. PINCODE: Extract ONLY the 6-digit number.
            8. CLEANING: Fix OCR errors (e.g., 'O' to '0' or 'I' to '1' in numbers and pincodes).
            9. EMPTY FIELDS: If a piece of info is not found, use an empty string "".
            10. RESPONSE: Respond ONLY with the JSON dictionary. No extra text.
            """
            response = model.generate_content(prompt)
            # Remove possible markdown formatting
            clean_json = response.text.strip().replace('```json', '').replace('```', '')
            data = json.loads(clean_json)

            # 🛡️ THE DEBUG PRINT: Look at your Django terminal for this!
            print("\n" + "="*50)
            print("🔍 GEMINI DATA EXTRACTION RESULT:")
            print(json.dumps(data, indent=4))
            print("="*50 + "\n")

            return data
        except Exception as e:
            print(f"Gemini Master Extraction Error: {e}")
            return {}