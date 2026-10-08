# UI/UX review checklist

Only flag what the diff touches.

## States
Every data-driven view needs loading, empty, error and success states. A new list or fetch with no empty state is a finding.

## Accessibility
- Interactive behaviour on `div`/`span` instead of `button`/`a`.
- Images without `alt`; decorative images without `alt=""`.
- Form inputs with no associated `<label>` or `aria-label`.
- Icon-only buttons with no accessible name.
- Focus visibly removed (`outline: none`) without a replacement.
- Colour as the only carrier of meaning.
- `tabIndex` greater than zero.
- Modal or drawer without focus trap and Escape handling.

## Interaction
- Destructive action without confirmation or undo.
- Submit button not disabled while a mutation is in flight.
- Mutation with no success or failure feedback.
- Error text that shows a raw API message to the user.

## Layout
- Fixed pixel widths where the container should flex.
- New view with no narrow-viewport consideration.
- Text that will overflow on long content with no truncation.

## Consistency
Compare against neighbouring components. A new spacing scale, colour literal, or one-off button variant where a design-system token exists is a finding.

## Forms
- Validation only on submit when inline would help.
- No distinction between field-level and form-level errors.
- Loss of entered data on error.
