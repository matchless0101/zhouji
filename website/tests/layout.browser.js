// Run this function with the browser testing tool against the local preview.
async (page) => {
  const results = [];
  for (const width of [320, 390, 760, 768, 1024, 1280, 1536]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('http://127.0.0.1:4173/');
    await page.locator('.pages-section').scrollIntoViewIfNeeded();
    await page.locator('.phone-lineup').evaluate(async image => {
      if (image instanceof HTMLImageElement) await image.decode();
    });
    const layout = await page.locator('.pages-section').evaluate(section => {
      const image = section.querySelector('.phone-lineup');
      const copy = section.querySelector('.pages-copy');
      const a = image.getBoundingClientRect();
      const b = copy.getBoundingClientRect();
      const container = section.querySelector('.wrap').getBoundingClientRect();
      const s = section.getBoundingClientRect();
      return {
        viewport: innerWidth,
        insideColumn: a.left >= container.left - 1 && a.right <= container.right + 1,
        insideSection: a.top >= s.top - 1 && a.bottom <= s.bottom + 1 && b.top >= s.top - 1 && b.bottom <= s.bottom + 1,
        separation: innerWidth > 760 ? b.left - a.right : a.top - b.bottom,
        completeImage: image.complete && image.naturalWidth > 0,
        aspectPreserved: Math.abs(a.width / a.height - image.naturalWidth / image.naturalHeight) < 0.01,
        overflow: document.documentElement.scrollWidth > innerWidth,
      };
    });
    if (!layout.insideColumn || !layout.insideSection || layout.separation < 19 || !layout.completeImage || !layout.aspectPreserved || layout.overflow) {
      throw new Error(`Phone showcase layout regression: ${JSON.stringify(layout)}`);
    }
    results.push(layout);
  }
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.locator('.pages-section').scrollIntoViewIfNeeded();
  return results;
}
