"""
Docling REST API Wrapper
Provides a simple HTTP API for document conversion using Docling
"""
from fastapi import FastAPI, UploadFile, File, HTTPException
from docling.document_converter import DocumentConverter
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title='Docling Document Processor',
    version='1.0.0',
    description='Document processing service for RAG workflows'
)

# Initialize converter once at startup
converter = DocumentConverter()
logger.info("Docling Document Converter initialized")

@app.get('/health')
def health():
    """Health check endpoint"""
    return {'status': 'healthy', 'service': 'docling'}

@app.get('/ready')
def ready():
    """Readiness check endpoint"""
    return {'status': 'ready', 'service': 'docling'}

@app.post('/convert')
async def convert_document(
    file: UploadFile = File(...),
    format: str = 'markdown'
):
    """
    Convert document to specified format
    
    Supported formats: markdown, json, html
    """
    logger.info(f"Converting document: {file.filename} to {format}")
    
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name
    
    try:
        result = converter.convert(tmp_path)
        
        if format == 'markdown':
            return {
                'format': 'markdown',
                'filename': file.filename,
                'content': result.document.export_to_markdown()
            }
        elif format == 'json':
            return {
                'format': 'json',
                'filename': file.filename,
                'data': result.document.export_to_dict()
            }
        elif format == 'html':
            return {
                'format': 'html',
                'filename': file.filename,
                'content': result.document.export_to_html()
            }
        else:
            raise HTTPException(
                status_code=400,
                detail=f'Unsupported format: {format}. Use markdown, json, or html.'
            )
    except Exception as e:
        logger.error(f"Error converting document: {str(e)}")
        raise HTTPException(status_code=500, detail=f'Conversion failed: {str(e)}')
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
