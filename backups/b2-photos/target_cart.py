#!/usr/bin/env python3
"""
Target.com Shopping Cart Automation - 1st Grade Supplies
Searches for each item, finds cheapest, adds to cart.
Reads credentials from ~/.hermes/.env
"""
import time
import sys
import subprocess
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

# Read credentials from .env
def get_env(key):
    result = subprocess.run(
        ["bash", "-c", f'source ~/.hermes/.env 2>/dev/null; echo "${key}"'],
        capture_output=True, text=True
    )
    return result.stdout.strip()

EMAIL = get_env("TARGET_USERNAME")
PASSWORD = get_env("TARGET_PASSWORD")

ZIP_CODE = "78653"

# 1st Grade Supply List: (search_term, quantity, human_label)
SUPPLY_LIST = [
    # Homeroom
    ("chisel tip highlighters", 1, "2x highlighters chisel tip (1 pack)"),
    ("wide ruled composition book", 2, "2x composition books wide ruled"),
    ("half blank composition book drawing", 2, "2x half-blank composition notebooks"),
    ("red plastic folder pockets brads", 1, "1x RED plastic folder w/ pockets & brads"),
    ("orange plastic folder pockets brads", 1, "1x ORANGE plastic folder w/ pockets & brads"),
    ("colored pencils pack", 1, "1x pkg colored pencils"),
    ("washable markers pack", 2, "2x pkg color markers"),
    ("white erasers pack", 3, "3x packs white erasers"),
    ("glue sticks 12 pack", 1, "12x glue sticks (1 bulk pack)"),
    ("school glue bottles", 2, "2x bottles of glue"),
    ("crayola crayons 24 pack", 2, "2x boxes Crayola 24-pack crayons"),
    ("play doh 4 pack", 1, "1x play-doh 4-pack"),
    ("ticonderoga pencils 12 pack", 2, "2x Ticonderoga 12-pack pencils"),
    ("blunt tip kids scissors", 1, "1x blunt child-size scissors"),
    ("expo dry erase markers", 1, "6x dry erase expo markers (1 pack)"),
    ("small whiteboard", 1, "1x whiteboard (no oversized)"),
    ("facial tissues", 2, "2x boxes of tissues"),
    ("disinfecting wipes canister", 1, "1x disinfecting wipes"),
    ("hand sanitizer pump", 1, "1x hand sanitizer"),
    ("sandwich bags ziploc", 1, "1x box sandwich ziploc bags"),
    ("gallon bags ziploc", 1, "1x box gallon ziploc bags"),
    ("white cardstock paper", 1, "1x pack plain cardstock"),
    ("colored cardstock paper", 1, "1x pack colored cardstock"),
    ("index cards 100 count", 2, "2x packs 100 index cards"),
    ("index card ring", 1, "1x index card ring"),
    ("12 inch ruler", 1, "1x ruler"),
    ("pencil box kids", 1, "1x pencil box"),
    ("kids lunch box", 1, "1x lunch box"),
    ("kids water bottle", 1, "1x water bottle"),
    ("kids backpack", 1, "1x backpack (no roller)"),
    ("seat sack chair pocket organizer", 1, "1x seat sack RED/BLUE"),
    # Arabic
    ("yellow plastic folder pockets brads", 1, "Arabic: 1x yellow plastic folder"),
    ("yellow composition notebook wide ruled", 1, "Arabic: 1x yellow composition notebook"),
    ("highlighter", 1, "Arabic: 1x highlighter"),
    # Islamic Studies
    ("green plastic folder pockets brads", 1, "Islamic Studies: 1x green plastic folder"),
]


def login(page):
    print("[*] Navigating to Target login...")
    page.goto("https://www.target.com/login", wait_until="domcontentloaded", timeout=30000)
    time.sleep(4)

    print("[*] Entering email...")
    email_sel = page.locator('input[name="email-address"]').first
    email_sel.wait_for(timeout=15000)
    email_sel.fill(EMAIL)
    time.sleep(1)

    # Target has a "Sign in or create account" button on the main page
    # or "Continue" on the login flow
    continue_btn = page.locator('button:has-text("Continue"), button:has-text("Sign in or create account")')
    continue_btn.first.click()
    time.sleep(4)

    try:
        pw_btn = page.locator('button:has-text("Enter your password")')
        pw_btn.wait_for(timeout=8000)
        pw_btn.click()
        time.sleep(2)
    except PlaywrightTimeout:
        print("[*] Already on password page")

    print("[*] Entering password...")
    pw_field = page.locator('input[type="password"], input[name="password"]').first
    pw_field.wait_for(timeout=10000)
    pw_field.fill(PASSWORD)
    time.sleep(1)

    page.locator('button:has-text("Sign in")').first.click()
    time.sleep(6)

    try:
        page.locator('a:has-text("Hi,"), a:has-text("Account")').first.wait_for(timeout=20000)
        print("[+] Logged in successfully!")
        return True
    except PlaywrightTimeout:
        if "account" in page.url or page.url.rstrip("/").endswith("target.com"):
            print("[+] Appears logged in")
            return True
        return False


def search_and_add(page, search_term, quantity, label):
    """Search, find cheapest, navigate to product, add to cart."""
    print(f"  Searching: '{search_term}'")

    url = f"https://www.target.com/s?searchTerm={search_term.replace(' ', '+')}"
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=25000)
        time.sleep(5)
    except PlaywrightTimeout:
        print("  [!] Search timeout")
        return False, None

    # Find product links
    links = page.locator('a[href*="/p/"]')
    link_count = links.count()
    if link_count == 0:
        print("  [!] No products found")
        return False, None

    # Get first product URL
    href = None
    for i in range(min(link_count, 5)):
        h = links.nth(i).get_attribute("href")
        if h and "/p/" in h and h.startswith("/"):
            href = h
            break
    
    if not href:
        print("  [!] No valid product links")
        return False, None

    product_url = f"https://www.target.com{href}"
    print(f"  Opening: {product_url[:80]}...")

    try:
        page.goto(product_url, wait_until="domcontentloaded", timeout=25000)
        time.sleep(5)
    except PlaywrightTimeout:
        print("  [!] Product page timeout")
        return False, None

    # Get product info
    title = "Unknown"
    try:
        title = page.locator("h1").first.text_content(timeout=5000) or "Unknown"
        title = title.strip()[:100]
    except:
        pass
    print(f"  Product: {title}")

    # Select shipping delivery method
    try:
        ship_btn = page.locator('button:has-text("shipping")')
        if ship_btn.count() > 0 and ship_btn.first.is_visible(timeout=3000):
            ship_btn.first.click()
            time.sleep(3)
    except:
        pass

    # Set quantity
    if quantity > 1:
        try:
            qty_btn = page.locator('button:has-text("Qty")')
            if qty_btn.count() > 0:
                qty_btn.first.click()
                time.sleep(1)
                opt = page.locator(f'li:has-text("{quantity}")').first
                opt.click()
                time.sleep(1)
                print(f"  Qty set to {quantity}")
        except:
            print("  [!] Could not change qty")

    # Add to cart
    try:
        add_btn = page.locator('button:has-text("Add to cart")')
        add_btn.first.wait_for(state="visible", timeout=15000)
        add_btn.first.click()
        time.sleep(4)
        print("  [+] ADDED TO CART")
        return True, title
    except PlaywrightTimeout:
        # Scroll and retry
        page.evaluate("window.scrollBy(0, 400)")
        time.sleep(2)
        try:
            add_btn = page.locator('button:has-text("Add to cart")')
            add_btn.first.click(timeout=8000)
            time.sleep(4)
            print("  [+] ADDED TO CART (after scroll)")
            return True, title
        except:
            print("  [!] Could not click Add to cart")
            return False, title
    except Exception as e:
        print(f"  [!] Error: {e}")
        return False, title


def main():
    success_list = []
    fail_list = []

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=False,
            slow_mo=300,
            args=["--disable-blink-features=AutomationControlled"]
        )
        context = browser.new_context(
            viewport={"width": 1280, "height": 900},
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = context.new_page()

        if not login(page):
            print("[!] LOGIN FAILED. Exiting.")
            browser.close()
            sys.exit(1)

        for i, (search, qty, label) in enumerate(SUPPLY_LIST):
            print(f"\n[{i+1}/{len(SUPPLY_LIST)}] {label}")
            try:
                ok, detail = search_and_add(page, search, qty, label)
                if ok:
                    success_list.append((label, detail or ""))
                else:
                    fail_list.append((label, detail or ""))
            except Exception as e:
                print(f"  [!] Unexpected: {e}")
                fail_list.append((label, str(e)))
            time.sleep(1)

        # Summary
        print(f"\n{'='*60}")
        print(f"DONE: {len(success_list)} added, {len(fail_list)} failed out of {len(SUPPLY_LIST)} items")
        print(f"{'='*60}")
        for label, detail in success_list:
            print(f"  [+] {label}")
        if fail_list:
            print(f"\nFailed:")
            for label, detail in fail_list:
                print(f"  [-] {label} ({detail[:60]})")

        print(f"\nBrowser open for cart review. Ctrl+C to close.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        browser.close()


if __name__ == "__main__":
    main()
