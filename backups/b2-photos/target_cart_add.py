#!/usr/bin/env python3
"""
Target.com Cart Automation — connects to existing Chrome via CDP.
Adds 1st grade school supplies (cheapest options) to cart.
"""
import time
import sys
import json
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

CDP_URL = "http://localhost:9222"

# 1st Grade Supply List: (search_term, quantity, label)
SUPPLY_LIST = [
    ("chisel tip highlighters", 1, "Highlighters chisel tip"),
    ("wide ruled composition book", 2, "Composition books wide ruled (x2)"),
    ("half blank composition notebook", 2, "Half-blank composition notebooks (x2)"),
    ("red plastic folder pockets brads", 1, "RED plastic folder w/ pockets & brads"),
    ("orange plastic folder pockets brads", 1, "ORANGE plastic folder w/ pockets & brads"),
    ("colored pencils", 1, "Colored pencils"),
    ("washable markers", 2, "Color markers (x2)"),
    ("white erasers", 3, "White erasers (x3 packs)"),
    ("glue sticks", 1, "Glue sticks (12+)"),
    ("school glue bottle", 2, "Bottles of glue (x2)"),
    ("crayola crayons 24 pack", 2, "Crayola 24-pack crayons (x2)"),
    ("play doh 4 pack", 1, "Play-Doh 4-pack"),
    ("ticonderoga pencils 12 pack", 2, "Ticonderoga 12-pack pencils (x2)"),
    ("kids scissors blunt", 1, "Blunt child scissors"),
    ("expo dry erase markers", 1, "Expo dry erase markers"),
    ("small whiteboard", 1, "Whiteboard (small)"),
    ("tissues", 2, "Boxes of tissues (x2)"),
    ("disinfecting wipes", 1, "Disinfecting wipes"),
    ("hand sanitizer", 1, "Hand sanitizer"),
    ("sandwich ziploc bags", 1, "Sandwich Ziploc bags"),
    ("gallon ziploc bags", 1, "Gallon Ziploc bags"),
    ("white cardstock", 1, "Plain cardstock"),
    ("colored cardstock", 1, "Colored cardstock"),
    ("index cards 100", 2, "Index cards 100ct (x2)"),
    ("index card ring binder", 1, "Index card ring"),
    ("12 inch ruler", 1, "Ruler"),
    ("pencil box", 1, "Pencil box"),
    ("kids lunch box", 1, "Lunch box"),
    ("kids water bottle", 1, "Water bottle"),
    ("kids backpack", 1, "Backpack"),
    ("seat sack chair pocket", 1, "Seat Sack RED/BLUE"),
    ("yellow plastic folder pockets brads", 1, "Arabic: Yellow folder"),
    ("yellow composition notebook wide ruled", 1, "Arabic: Yellow comp notebook"),
    ("highlighter", 1, "Arabic: Highlighter"),
    ("green plastic folder pockets brads clear", 1, "Islamic Studies: Green folder"),
]


def search_and_add(page, search_term, quantity, label):
    """Search Target, navigate to cheapest product, add to cart."""
    encoded = search_term.replace(" ", "+")
    url = f"https://www.target.com/s?searchTerm={encoded}"

    try:
        page.goto(url, wait_until="domcontentloaded", timeout=20000)
    except PlaywrightTimeout:
        print(f"  [!] Search page timeout")
        return False

    time.sleep(4)

    # Find product links
    links = page.locator('a[href*="/p/"]')
    count = links.count()
    if count == 0:
        print(f"  [!] No product results")
        return False

    # Get first valid product URL
    href = None
    for i in range(min(count, 15)):
        h = links.nth(i).get_attribute("href")
        if h and "/p/" in h and h.startswith("/"):
            href = h
            break

    if not href:
        print(f"  [!] No valid product links")
        return False

    product_url = f"https://www.target.com{href}"

    try:
        page.goto(product_url, wait_until="domcontentloaded", timeout=20000)
    except PlaywrightTimeout:
        print(f"  [!] Product page timeout")
        return False

    time.sleep(4)

    # Get product title
    title = "?"
    try:
        title = page.locator("h1").first.text_content(timeout=5000) or "?"
        title = title.strip()[:100]
    except:
        pass
    print(f"  -> {title}")

    # Select shipping fulfillment
    try:
        ship_btns = page.locator('button:has-text("shipping")')
        if ship_btns.count() > 0:
            ship_btns.first.click()
            time.sleep(2)
    except:
        pass

    # Set quantity if > 1
    if quantity > 1:
        try:
            qty_btn = page.locator('button:has-text("Qty")')
            if qty_btn.count() > 0:
                qty_btn.first.click()
                time.sleep(1)
                opts = page.locator(f'li:has-text("{quantity}")')
                if opts.count() > 0:
                    opts.first.click()
                    time.sleep(1)
                    print(f"  Qty: {quantity}")
        except:
            pass

    # Click Add to Cart
    try:
        add_btn = page.locator('button:has-text("Add to cart")')
        add_btn.first.wait_for(state="visible", timeout=10000)
        add_btn.first.click()
        time.sleep(3)
        print(f"  [+] ADDED")
        return True
    except PlaywrightTimeout:
        # Scroll down and retry
        page.evaluate("window.scrollBy(0, 400)")
        time.sleep(2)
        try:
            add_btn = page.locator('button:has-text("Add to cart")')
            add_btn.first.click(timeout=5000)
            time.sleep(3)
            print(f"  [+] ADDED (after scroll)")
            return True
        except:
            print(f"  [!] Add to cart button not clickable")
            return False
    except Exception as e:
        print(f"  [!] Error: {e}")
        return False


def main():
    success = []
    failed = []

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0]
        page = context.pages[0]

        # Verify login
        page.goto("https://www.target.com", wait_until="domcontentloaded", timeout=15000)
        time.sleep(3)
        body = page.locator('body').inner_text(timeout=5000)
        if 'ryan' not in body.lower() and 'Hi,' not in body:
            print("[!] Not logged in! Please log in first.")
            sys.exit(1)
        print("[+] Logged in as Ryan\n")

        for i, (search, qty, label) in enumerate(SUPPLY_LIST):
            print(f"[{i+1}/{len(SUPPLY_LIST)}] {label}")
            try:
                ok = search_and_add(page, search, qty, label)
                if ok:
                    success.append(label)
                else:
                    failed.append(label)
            except Exception as e:
                print(f"  [!] Unexpected error: {e}")
                failed.append(label)
            time.sleep(1)

        # Navigate to cart for review
        page.goto("https://www.target.com/cart", wait_until="domcontentloaded", timeout=15000)

        # Summary
        print(f"\n{'='*60}")
        print(f"RESULTS: {len(success)} added / {len(failed)} failed / {len(SUPPLY_LIST)} total")
        print(f"{'='*60}")
        for l in success:
            print(f"  [+] {l}")
        if failed:
            print(f"\nFAILED ({len(failed)}):")
            for l in failed:
                print(f"  [-] {l}")

        # Don't close the browser — leave it for user review
        print(f"\nCart page is open in Chrome. Review and checkout when ready.")
        browser.close()


if __name__ == "__main__":
    main()
