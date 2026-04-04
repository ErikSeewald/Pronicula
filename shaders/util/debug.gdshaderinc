// Draws the given int by drawing squares onto a grid where each column represents a digit
// and the height from bottom to top represents that digit's value.
// The limit to 5 digits and specifically integers is chosen because decimals and greater digit
// counts do not work well with this method of rendering.
vec3 debug_draw_int_5_digits(int number, vec2 uv)
{
	const int digits = 5;
	
	// Indicate if the number is too large
	if (float(number) >= pow(10.0, float(digits))) { return vec3(0.0); }
	
	vec3 color = vec3(0.5, 0.2, 0.4);
	int column = int(uv.x * float(digits));
	int row = int(uv.y * 10.0);
	
	int digit_idx = digits - column; // Greatest digit at the leftmost position
	int digit_value = int(float(number) / pow(10.0, float(digit_idx - 1))) % 10;
	
	if (row > 9 - digit_value) { color = vec3(0.0); } // Count up from botton row to top row
	
	// GRID_LINES
	vec2 uv_mod = mod(uv, vec2(1.0 / float(digits), 0.1)); 
	if (uv_mod.x < 0.01 || uv_mod.y < 0.01 || uv.x < 0.03 || uv.y < 0.03) 
	{ 
		color = vec3(1.0, 0.0, 0.5); 
	}
	
	return color;
}