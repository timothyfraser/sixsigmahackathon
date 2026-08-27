"""
Minimal FastAPI application for the Six Sigma Hackathon.
"""

from fastapi import FastAPI
from fastapi.responses import RedirectResponse

app = FastAPI(
    title="FastAPI Example API",
    description="FastAPI example description.",
    version="1.0.0"
)


@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "FastAPI is running!", "docs": "/docs"}


@app.get("/echo")
async def echo(msg: str = ""):
    """Echo back the input."""
    return {"msg": f"The message is: '{msg}'"}


@app.post("/sum")
async def sum_numbers(a: float, b: float):
    """Return the sum of two numbers."""
    return {"result": a + b}


@app.get("/__docs__/")
async def docs_redirect():
    """Redirect to FastAPI interactive documentation."""
    return RedirectResponse(url="/docs")
