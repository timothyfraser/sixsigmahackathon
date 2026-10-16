"""
Minimal FastAPI application for the Six Sigma Hackathon.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

app = FastAPI(
    title="FastAPI Example API",
    description="FastAPI example description.",
    version="1.0.0"
)

# Let a browser frontend on another address (e.g. demos/reactfront on localhost:5173)
# call this API. Fine for a hackathon demo; list your real frontend URL in
# allow_origins before you put anything private behind an API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
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
