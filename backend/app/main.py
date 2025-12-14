from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
from PIL import Image
import pytesseract
import io

app = FastAPI()

class OCRResponse(BaseModel):
    text: str

@app.get("/health")
def health():
    return {"status": "ok", "message": "backend is running"}

@app.post("/ocr", response_model=OCRResponse)
async def ocr_api(image: UploadFile = File(...)):
    # Read uploaded file
    img_bytes = await image.read()
    img = Image.open(io.BytesIO(img_bytes))

    # Apply OCR
    text = pytesseract.image_to_string(img)

    return {"text": text.strip()}
