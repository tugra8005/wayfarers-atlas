# Atlas (Java) karşılaştırması

Savaş Takan'ın Atlas kodu bu depoda yok; özgün hâli: https://github.com/savastakan/atlas (`1748ccf`).

`java/RefMain.java` bizim: Atlas'ın `Main.java`'sı dosya yolunu sabit yazdığı için, `.fsm` dosyasını argüman olarak alıp test dizisini yazdırır. Lua karşılığının Java ile aynı çıktıyı verdiğini denetlemek için:

```bash
git clone https://github.com/savastakan/atlas /tmp/atlas && git -C /tmp/atlas checkout 1748ccf
```

```bash
javac -d /tmp/jref /tmp/atlas/*.java reference/java/RefMain.java && luajit tools/compare_java.lua /tmp/jref tests/fixtures/bbtas.fsm
```

Testler (`tests/run.lua`) Java'ya gerek duymaz: Java çıktıları `tests/fixtures/*.java.txt` içinde saklıdır.
