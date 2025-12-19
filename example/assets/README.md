# Test Assets

Place test images here for printing demonstrations.

## Required Files

- `test_label.png` - Default test image used by the example app

## Image Requirements

- **Format**: PNG, JPG, or any format supported by the `image` package
- **Size**: Any size (will be automatically resized to fit printer width of 384px)
- **Color**: Any (will be converted to monochrome with dithering)

## Creating Test Images

You can create simple test labels using any image editor or online tools:

1. Create a 384x600px image (or any size, it will be resized)
2. Add text, QR codes, barcodes, logos, etc.
3. Save as PNG or JPG
4. Place in this `assets/` folder
5. Update the filename in `lib/main.dart` if different from `test_label.png`

## Example Content Ideas

- Company logo
- Product information
- QR codes with URLs
- Barcodes (EAN13, CODE128, etc.)
- Shipping labels
- Name tags
- Price tags
