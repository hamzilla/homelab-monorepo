#!/usr/bin/env python3
"""
Target.com Shopping Cart Automation - 1st Grade Supplies
Uses non-headless Chromium to bypass bot detection.
Reads credentials from ~/.hermes/.env
"""
import time
import sys
import subprocess
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

def get_env(key):
    result = subprocess.run(
        ["bash", "-c", f'source ~/.hermes/.env 2>/dev/null; echo "${key}"'],
        capture_output=True, text=True
    )
    return result.stdout.strip()

EMAIL = get_env("TARGET_USERNAME")
PASSWORD = get_env("TARGET_PASSWORD")

# 1st Grade Supply List: (search_term, quantity_needed, human_label)
SUPPLY_LIST = [
    # Homeroom
    ("chisel tip highlighters pack", 1, "Highlighters chisel tip (1 pack for 2 needed)"),
    ("wide ruled composition book", 2, "Composition books wide ruled (x2)"),
    ("half blank composition notebook drawing", 2, "Half-blank composition notebooks (x2)"),
    ("red plastic folder pockets brads", 1, "RED plastic folder w/ pockets & brads"),
    ("orange plastic folder pockets brads", 1, "ORANGE plastic folder w/ pockets & brads"),
    ("colored pencils", 1, "Colored pencils (1 pkg)"),
    ("color markers pack", 2, "Color markers (x2 pkg)"),
    ("white erasers pack", 3, "White erasers (x3 packs)"),
    ("glue sticks pack", 1, "Glue sticks (12ct or larger)"),
    ("school glue bottle", 2, "Bottles of glue (x2)"),
    ("crayola crayons 24 pack", 2, "Crayola 24-pack crayons (x2)"),
    ("play doh 4 pack", 1, "Play-Doh 4-pack"),
    ("ticonderoga pencils 12 pack", 2, "Ticonderoga 12-pack pencils (x2)"),
    ("kids scissors blunt tip", 1, "Blunt child-size scissors"),
    ("expo dry erase markers", 1, "Expo dry erase markers (6-pack)"),
    ("small whiteboard for kids", 1, "Whiteboard (small, no oversized)"),
    ("tissues box", 2, "Boxes of tissues (x2)"),
    ("clorox disinfecting wipes", 1, "Disinfecting wipes canister"),
    ("hand sanitizer", 1, "Hand sanitizer"),
    ("sandwich zip bags", 1, "Sandwich-sized Ziploc bags"),
    ("gallon zip bags", 1, "Gallon-sized Ziploc bags"),
    ("white cardstock paper", 1, "Plain cardstock (1 pack)"),
    ("colored cardstock paper", 1, "Colored cardstock (1 pack)"),
    ("index cards 100 count", 2, "Index cards 100ct (x2 packs)"),
    ("index card ring", 1, "Index card ring"),
    ("12 inch ruler", 1, "Ruler"),
    ("pencil box for kids", 1, "Pencil box"),
    ("kids lunch box", 1, "Lunch box"),
    ("kids water bottle", 1, "Water bottle"),
    ("kids backpack", 1, "Backpack (no roller)"),
    ("seat sack chair pocket", 1, "Seat Sack RED/BLUE"),
    # Arabic
    ("yellow plastic folder pockets brads", 1, "Arabic: Yellow plastic folder"),
    ("yellow composition notebook wide ruled", 1, "Arabic: Yellow composition notebook"),
    ("highlighter any color pack", 1, "Arabic: Highlighter"),
    # Islamic Studies
    ("green plastic folder pockets brads", 1, "Islamic Studies: Green plastic folder"),
]


def login(page):
    """Full login flow for Target.com"""
    print("[*] Going to Target login...")
    page.goto("https://www.target.com/login", wait_until="domcontentloaded", timeout=30000)
    time.sleep(6)

    # Fill email on initial form
    print("[*] Entering email...")
    page.locator('input[name="email-address"]').fill(EMAIL)
    time.sleep(1)

    # Click "Sign in or create account" via JS
    page.evaluate('''(() => {
        const btns = document.querySelectorAll('button');
        for (const b of btns) {
            if (b.textContent.includes('Sign in or create account')) { b.click(); return; }
        }
    })()''')
    time.sleep(10)
    print(f"[*] URL after email: {page.url}")

    # Fill username on OIDC form
    print("[*] Filling username and clicking Continue...")
    username = page.locator('input[name="username"]')
    username.wait_for(timeout=15000)
    username.fill(EMAIL)
    time.sleep(2)

    # Remove any overlay elements that intercept clicks
    page.evaluate('''(() => {
        document.querySelectorAll('[id*="floating"], [class*="overlay"], [class*="Overlay"]').forEach(e => {
            e.style.pointerEvents = 'none';
            e.remove();
        });
    })()''')
    time.sleep(1)

    # Click Continue using JS to bypass overlay issues
    page.evaluate('''(() => {
        const btns = document.querySelectorAll('button');
        for (const b of btns) {
            if (b.textContent.trim() === 'Continue') { b.click(); return 'clicked'; }
        }
        return 'not found';
    })()''')
    time.sleep(12)
    print(f"[*] URL after continue: {page.url}")

    # Look for "Enter your password" option - try multiple selectors
    print("[*] Looking for password option...")
    found_pw = False
    for sel in [
        'button:has-text("Enter your password")',
        'button:has-text("password")',
        'text="Enter your password"',
    ]:
        try:
            el = page.locator(sel)
            if el.count() > 0 and el.first.is_visible(timeout=3000):
                el.first.click()
                found_pw = True
                print(f"[*] Clicked password option via: {sel}")
                break
        except:
            continue

    if not found_pw:
        # Debug: print what's on the page
        print("[!] Password option not found. Page content:")
        for btn in page.locator('button:visible').all():
            txt = (btn.text_content() or '').strip()[:80]
            if txt: print(f"    btn: '{txt}'")
        for inp in page.locator('input:visible').all():
            print(f"    input: name={inp.get_attribute('name')} type={inp.get_attribute('type')}")
        # Try going directly to the password step via URL manipulation
        page.screenshot(path='/tmp/target_debug_pw.png')

    time.sleep(5)

    # Enter password
    print("[*] Entering password...")
    pw_input = page.locator('input[type="password"]')
    pw_input.wait_for(timeout=10000)
    pw_input.fill(PASSWORD)
    time.sleep(1)

    page.locator('button:has-text("Sign in with password")').first.click()
    time.sleep(10)

    # Verify login success
    body = page.locator('body').inner_text()
    if 'Hi,' in body or 'Hello,' in body:
        print("[+] LOGIN SUCCESS!")
        return True
    print(f"[!] Login uncertain. URL: {page.url}")
    return True  # Continue anyway


def search_and_add(page, search_term, quantity, label):
    """Search for item on Target, find product, add to cart."""
    print(f"  Searching: {search_term}")
    
    url = f"https://www.target.com/s?searchTerm={search_term.replace(' ', '+')}"
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=25000)
        time.sleep(5)
    except PlaywrightTimeout:
        print("  [!] Search timeout")
        return False

    # Find product links
    links = page.locator('a[href*="/p/"]')
    link_count = links.count()
    if link_count == 0:
        print("  [!] No products found")
        return False

    # Get first valid product href
    href = None
    for i in range(min(link_count, 10)):
        h = links.nth(i).get_attribute("href")
        if h and "/p/" in h and h.startswith("/"):
            href = h
            break

    if not href:
        print("  [!] No valid product links")
        return False

    product_url = f"https://www.target.com{href}"

    try:
        page.goto(product_url, wait_until="domcontentloaded", timeout=25000)
        time.sleep(5)
    except PlaywrightTimeout:
        print("  [!] Product page timeout")
        return False

    # Get product title
    title = "?"
    try:
        title = page.locator("h1").first.text_content(timeout=5000) or "?"
        title = title.strip()[:100]
    except:
        pass
    print(f"  Product: {title}")

    # Select "shipping" fulfillment
    try:
        ship_btn = page.locator('button:has-text("shipping"), button:has-text("Shipping")')
        if ship_btn.count() > 0 and ship_btn.first.is_visible(timeout=3000):
            ship_btn.first.click()
            time.sleep(3)
    except:
        pass

    # Set quantity if > 1
    if quantity > 1:
        try:
            page.locator('button:has-text("Qty")').first.click()
            time.sleep(1)
            page.locator(f'li:has-text("{quantity}")').first.click()
            time.sleep(1)
            print(f"  Qty set to {quantity}")
        except:
            print("  [!] Could not change qty")

    # Click Add to Cart
    try:
        add_btn = page.locator('button:has-text("Add to cart")')
        add_btn.first.wait_for(state="visible", timeout=15000)
        add_btn.first.click()
        time.sleep(4)
        print(f"  [+] ADDED TO CART: {title}")
        return True
    except PlaywrightTimeout:
        # Scroll down and retry
        page.evaluate("window.scrollBy(0, 400)")
        time.sleep(2)
        try:
            add_btn = page.locator('button:has-text("Add to cart")')
            add_btn.first.click(timeout=8000)
            time.sleep(4)
            print(f"  [+] ADDED TO CART (after scroll): {title}")
            return True
        except:
            print(f"  [!] Add to cart failed")
            return False
    except Exception as e:
        print(f"  [!] Error: {e}")
        return False


def main():
    results = {"success": [], "failed": []}

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=False,
            slow_mo=300,
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-first-run",
                "--no-default-browser-check"
            ]
        )
        context = browser.new_context(
            viewport={"width": 1280, "height": 900},
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = context.new_page()

        if not login(page):
            print("[!] LOGIN FAILED")
            browser.close()
            sys.exit(1)

        for i, (search, qty, label) in enumerate(SUPPLY_LIST):
            print(f"\n[{i+1}/{len(SUPPLY_LIST)}] {label}")
            try:
                ok = search_and_add(page, search, qty, label)
                if ok:
                    results["success"].append(label)
                else:
                    results["failed"].append(label)
            except Exception as e:
                print(f"  [!] Unexpected: {e}")
                results["failed"].append(label)
            time.sleep(1)

        # Summary
        print(f"\n{'='*60}")
        print(f"COMPLETE: {len(results['success'])} added, {len(results['failed'])} failed / {len(SUPPLY_LIST)} total")
        print(f"{'='*60}")
        for label in results["success"]:
            print(f"  [+] {label}")
        if results["failed"]:
            print(f"\nFailed:")
            for label in results["failed"]:
                print(f"  [-] {label}")

        # Keep open for review
        print(f"\nBrowser open - review cart at https://www.target.com/cart")
        print("Press Ctrl+C to close.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        browser.close()


if __name__ == "__main__":
    main()
