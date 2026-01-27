
import pandas as pd
import sys

try:
    file_path = 'Sample.xlsx'
    xl = pd.ExcelFile(file_path)
    
    with open('excel_analysis.txt', 'w', encoding='utf-8') as f:
        f.write(f"Sheet names: {xl.sheet_names}\n")
        
        # Read the first sheet
        df = xl.parse(xl.sheet_names[0])
        
        f.write("\n--- Columns ---\n")
        f.write(str(df.columns.tolist()) + "\n")
        
        f.write("\n--- First 5 Rows ---\n")
        f.write(df.head().to_string() + "\n")
        
        f.write("\n--- Data Types ---\n")
        f.write(str(df.dtypes) + "\n")
        
    print("Analysis complete. Written to excel_analysis.txt")

except Exception as e:
    print(f"Error reading Excel file: {e}")
