"""Run HTML browser smoke tests without needing a hosted server.
Prerequisites: Python 3.10+, playwright package, Chromium browser.
Use: python scripts/preview_smoke_test.py
No external network calls are needed.
"""
import asyncio
import base64
from pathlib import Path
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
HTML = (ROOT / 'preview' / 'index.html').read_text(encoding='utf-8')
WALLPAPER = base64.b64encode((ROOT / 'preview' / 'assets' / 'demo_wallpaper.svg').read_bytes()).decode()
HTML = HTML.replace('assets/demo_wallpaper.svg', 'data:image/svg+xml;base64,' + WALLPAPER)

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path='/usr/bin/chromium', args=['--no-sandbox'])
        for name, (width, height) in [('desktop', (1440, 1000)), ('tablet', (1060, 780)), ('phone', (390, 844))]:
            page = await browser.new_page(viewport={'width': width, 'height': height})
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            await page.set_content(HTML)
            await page.screenshot(path=str(ROOT / 'qa' / (name + '.png')), full_page=True)
            assert await page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'{name} horizontal overflow'
            assert await page.locator('.device').count() == 4
            if name == 'desktop':
                await page.locator('#sidenav [data-nav="Settings"]').click()
                await page.locator('#sidenav [data-nav="Devices"]').click()
                assert await page.locator('#sessioncols .control-panel').count() == 1
                await page.locator('.device[data-device="0"]').click()
                assert await page.locator('#sessiontitle').inner_text() == 'Xiaomi Pad 5'
            if name == 'phone':
                assert await page.locator('#sessioncols').is_hidden()
                await page.locator('#mobilebar [data-nav="Remote Control"]').click()
                await page.screenshot(path=str(ROOT / 'qa' / 'phone_control.png'), full_page=True)
                await page.locator('#mobilebar [data-nav="Settings"]').click()
                await page.locator('[data-action="theme"]').click()
                assert await page.locator('body.light').count() == 1
                await page.locator('#mobilebar [data-nav="Devices"]').click()
                assert await page.locator('#sessioncols').is_hidden()
            assert not errors, f'JS errors in {name}: {errors}'
            print(f'PASS {name}: responsive, no JS errors')
            await page.close()
        await browser.close()

if __name__ == '__main__':
    asyncio.run(main())
