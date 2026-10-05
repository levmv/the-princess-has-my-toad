#!/usr/bin/env python3
"""Rasterize the shared SVG for raylib. Optional authoring tool: Playwright + Chrome.

The checked-in PNG is embedded in both game builds; normal builds need no browser.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parent.parent
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path='/usr/bin/google-chrome', headless=True,
                                args=['--no-sandbox'])
    page = browser.new_page(viewport={'width': 1328, 'height': 400}, device_scale_factor=1)
    page.set_content('<style>html,body{margin:0;background:transparent}'
                     'svg{display:block;width:100vw;height:100vh}</style>'
                     + (root / 'assets/logo.svg').read_text())
    page.screenshot(path=str(root / 'assets/logo.png'), omit_background=True)
    browser.close()
