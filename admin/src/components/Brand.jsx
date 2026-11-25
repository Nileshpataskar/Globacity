/** GlobaCity logo pieces, from the official SVGs in public/brand. */
export function BrandMark({ size = 36, tile = true, className = '' }) {
  return (
    <img
      src={tile ? './brand/app-icon.svg' : './brand/lettermark.svg'}
      width={size}
      height={size}
      alt="GlobaCity"
      className={className}
      style={{ display: 'block', flex: 'none' }}
    />
  );
}

export function Wordmark({ size = 20, onDark = false, mark = true }) {
  return (
    <span className="wordmark" style={{ fontSize: size }}>
      {mark && <BrandMark size={size * 1.55} tile={onDark} />}
      <span className={onDark ? 'wm-globa on-dark' : 'wm-globa'}>Globa</span>
      <span className="wm-city">City</span>
    </span>
  );
}
