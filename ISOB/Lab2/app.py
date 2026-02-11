
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

import caesar
import vigenere

LATIN_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
CYRILLIC_LETTERS = (
    "абвгдежзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
)
VALID_KEY_CHARS = set(LATIN_LETTERS + CYRILLIC_LETTERS)

SAMPLE_TEXT = """Hello, World! This is a secret message.
The quick brown fox jumps over the lazy dog.
Привет, мир! Это секретное сообщение."""


def validate_shift(value: str) -> tuple[bool, str]:
    """Shift must be integer in 0–25."""
    value = value.strip()
    if not value:
        return False, "Shift is required (0–25)."
    try:
        n = int(value)
    except ValueError:
        return False, "Shift must be a number."
    if n < 0 or n > 25:
        return False, "Shift must be between 0 and 25."
    return True, ""


def validate_key(value: str) -> tuple[bool, str]:
    """Key must be non-empty and letters only."""
    value = value.strip()
    if not value:
        return False, "Key is required."
    bad = [c for c in value if c not in VALID_KEY_CHARS]
    if bad:
        return False, "Key must contain only letters."
    return True, ""


def run():
    root = tk.Tk()
    root.title("Lab 2 — Caesar & Vigenère Cipher")
    root.geometry("560x480")
    root.resizable(True, True)

    main = ttk.Frame(root, padding=12)
    main.pack(fill=tk.BOTH, expand=True)

    cipher_choice = tk.StringVar(value="caesar")
    shift_var = tk.StringVar(value="3")
    key_var = tk.StringVar(value="key")
    status_var = tk.StringVar(
        value="Enter text, set shift (0–25) or key, then Encrypt or Decrypt."
    )

    ttk.Label(main, text="Cipher:").grid(row=0, column=0, sticky=tk.W, pady=(0, 4))
    cf = ttk.Frame(main)
    cf.grid(row=0, column=1, sticky=tk.W, pady=(0, 4))
    ttk.Radiobutton(
        cf, text="Caesar (shift)", variable=cipher_choice, value="caesar"
    ).pack(side=tk.LEFT, padx=(0, 12))
    ttk.Radiobutton(
        cf, text="Vigenère (key)", variable=cipher_choice, value="vigenere"
    ).pack(side=tk.LEFT)

    ttk.Label(main, text="Shift (0–25):").grid(row=1, column=0, sticky=tk.W, pady=4)
    shift_frame = ttk.Frame(main)
    shift_frame.grid(row=1, column=1, sticky=tk.W, pady=4)
    ttk.Spinbox(
        shift_frame, textvariable=shift_var, from_=0, to=25, width=6
    ).pack(side=tk.LEFT)

    ttk.Label(main, text="Key (letters):").grid(row=2, column=0, sticky=tk.W, pady=4)
    ttk.Entry(main, textvariable=key_var, width=24).grid(
        row=2, column=1, sticky=tk.W, pady=4
    )

    ttk.Label(main, text="Input text:").grid(
        row=3, column=0, sticky=tk.NW, pady=(8, 2)
    )
    input_text = scrolledtext.ScrolledText(
        main, height=8, width=50, wrap=tk.WORD, font=("Consolas", 10)
    )
    input_text.grid(row=4, column=0, columnspan=2, sticky=tk.NSEW, pady=(0, 8))

    ttk.Label(main, text="Output:").grid(row=5, column=0, sticky=tk.NW, pady=(4, 2))
    output_text = scrolledtext.ScrolledText(
        main,
        height=8,
        width=50,
        wrap=tk.WORD,
        font=("Consolas", 10),
        state=tk.DISABLED,
    )
    output_text.grid(row=6, column=0, columnspan=2, sticky=tk.NSEW, pady=(0, 8))

    btn_frame = ttk.Frame(main)
    btn_frame.grid(row=7, column=0, columnspan=2, sticky=tk.W, pady=8)

    def set_output(s: str):
        output_text.config(state=tk.NORMAL)
        output_text.delete("1.0", tk.END)
        output_text.insert(tk.END, s)
        output_text.config(state=tk.DISABLED)

    def do_encrypt():
        text = input_text.get("1.0", tk.END).strip()
        if not text:
            status_var.set("Enter some text to encrypt.")
            messagebox.showwarning("Validation", "Input text is empty.")
            return
        if cipher_choice.get() == "caesar":
            ok, err = validate_shift(shift_var.get())
            if not ok:
                status_var.set(err)
                messagebox.showwarning("Validation", err)
                return
            result = caesar.encrypt(text, int(shift_var.get()))
        else:
            ok, err = validate_key(key_var.get())
            if not ok:
                status_var.set(err)
                messagebox.showwarning("Validation", err)
                return
            result = vigenere.encrypt(text, key_var.get().strip())
        set_output(result)
        status_var.set("Encrypted.")

    def do_decrypt():
        text = input_text.get("1.0", tk.END).strip()
        if not text:
            status_var.set("Enter some text to decrypt.")
            messagebox.showwarning("Validation", "Input text is empty.")
            return
        if cipher_choice.get() == "caesar":
            ok, err = validate_shift(shift_var.get())
            if not ok:
                status_var.set(err)
                messagebox.showwarning("Validation", err)
                return
            result = caesar.decrypt(text, int(shift_var.get()))
        else:
            ok, err = validate_key(key_var.get())
            if not ok:
                status_var.set(err)
                messagebox.showwarning("Validation", err)
                return
            result = vigenere.decrypt(text, key_var.get().strip())
        set_output(result)
        status_var.set("Decrypted.")

    def load_sample():
        input_text.delete("1.0", tk.END)
        input_text.insert(tk.END, SAMPLE_TEXT)
        output_text.config(state=tk.NORMAL)
        output_text.delete("1.0", tk.END)
        output_text.config(state=tk.DISABLED)
        status_var.set(
            "Sample text loaded. Try Encrypt (Caesar shift 3 or Vigenère key 'secret')."
        )

    ttk.Button(btn_frame, text="Load sample", command=load_sample).pack(
        side=tk.LEFT, padx=(0, 8)
    )
    ttk.Button(btn_frame, text="Encrypt", command=do_encrypt).pack(
        side=tk.LEFT, padx=(0, 8)
    )
    ttk.Button(btn_frame, text="Decrypt", command=do_decrypt).pack(side=tk.LEFT)

    ttk.Label(main, text="Status:").grid(row=8, column=0, sticky=tk.NW, pady=2)
    ttk.Label(
        main, textvariable=status_var, wraplength=400, foreground="gray"
    ).grid(row=8, column=1, sticky=tk.W, pady=2)

    main.rowconfigure(4, weight=1)
    main.rowconfigure(6, weight=1)
    main.columnconfigure(1, weight=1)
    root.mainloop()


if __name__ == "__main__":
    run()
