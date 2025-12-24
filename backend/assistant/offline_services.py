import os
from django.conf import settings
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

class OfflineService:
    _tokenizer = None
    _model = None

    @classmethod
    def load_model(cls):
        """
        Loads the NLLB model into RAM.
        Runs only once when the server starts or on the first request.
        """
        if cls._model is None:
            print("⏳ Loading NLLB Offline AI... (This runs once)")
            try:
                # We use the Distilled 600M version. 
                model_name = "facebook/nllb-200-distilled-600M"
                
                cls._tokenizer = AutoTokenizer.from_pretrained(model_name)
                cls._model = AutoModelForSeq2SeqLM.from_pretrained(model_name)
                
                print("✅ NLLB Offline Model Loaded Successfully!")
            except Exception as e:
                print(f"❌ Error loading NLLB Model: {e}")
                cls._model = None

    @classmethod
    def get_translation(cls, text):
        """
        Translates text from English to Malayalam using NLLB.
        """
        # 1. Ensure the model is loaded
        cls.load_model()
        
        if cls._model is None:
            return "Error: Offline model failed to load."

        try:
            # 2. Set Language Codes
            # eng_Latn = English
            # mal_Mlym = Malayalam
            # Note: We don't need to set src_lang explicitly for the tokenizer in this specific way for all versions, 
            # but usually NLLB handles it by just tokenizing. 
            
            # 3. Prepare the input
            inputs = cls._tokenizer(text, return_tensors="pt")

            # 4. Generate Translation
            # FIX IS HERE: Use convert_tokens_to_ids instead of lang_code_to_id
            forced_bos_token_id = cls._tokenizer.convert_tokens_to_ids("mal_Mlym")
            
            translated_tokens = cls._model.generate(
                **inputs, 
                forced_bos_token_id=forced_bos_token_id,
                max_length=100
            )

            # 5. Decode the result back to text
            result = cls._tokenizer.batch_decode(translated_tokens, skip_special_tokens=True)[0]
            
            return result

        except Exception as e:
            print(f"NLLB Translation Error: {e}")
            return "Translation Failed"