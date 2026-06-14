# scale-to-zero-labs

ชุดตัวอย่าง + ไกด์แบบ **standalone** จากงานวิจัย scale-to-zero / unikernel / AI-SRE
แต่ละโฟลเดอร์เป็น **คนละเรื่อง แยกอิสระจากกัน** — หยิบไปใช้/ดัดแปลงทีละส่วนได้เลย

---

## ในนี้มีอะไร

| โฟลเดอร์ | เรื่อง | รันบนอะไร |
|----------|--------|-----------|
| [`nanos-microvm-lab/`](./nanos-microvm-lab/) | **Lab**: ติดตั้ง + บูต Nanos unikernel บน Firecracker microVM จริง → วัด cold-boot / snapshot / restore (turnkey, วัดสด ไม่มี hardcoded) | 🐧 Linux + KVM |
| [`topology/`](./topology/) | **ตัวอย่าง UI**: แท็บ Topology ไดอะแกรมระบบเคลื่อนไหว 60fps (SwiftUI · TimelineView + Canvas) + stub ให้คอมไพล์/รัน standalone ได้ | 🍎 macOS 13+ |
| [`live-agent-prompts/`](./live-agent-prompts/) | **Prompt engineering**: system prompt จริงที่ใช้ให้ SLM (qwen3-coder) เปลี่ยนประโยคเดียว → เว็บไซต์ HTML + output gate | 🤖 LLM ใด ๆ |

> แต่ละโฟลเดอร์มี `README.md` ของตัวเองอธิบายละเอียด (flow · โครงสร้าง · ข้อจำกัด · วิธีปรับใช้)

---

## เริ่มตรงไหนดี

- อยากเห็น **microVM scale-to-zero ทำงานจริง** → [`nanos-microvm-lab/TESTING-GUIDE.md`](./nanos-microvm-lab/TESTING-GUIDE.md)
- อยากทำ **dashboard/topology เคลื่อนไหว** → [`topology/README.md`](./topology/README.md) (มี `swift run` + ภาพตัวอย่าง)
- อยากให้ **AI สร้างเว็บจาก prompt** → [`live-agent-prompts/README.md`](./live-agent-prompts/README.md)

---

## หมายเหตุ

- ทุกส่วนเป็น **ไกด์/ตัวอย่าง** — ออกแบบให้นำไปต่อยอด/ดัดแปลงตามความเหมาะสมในการใช้งานจริง
- ตัวเลขในแล็บ = **วัดสดตอนรัน** (ไม่มี mock/hardcoded) · ตัวอย่างโค้ด = genericized ไม่มีข้อมูล infra ส่วนตัว
- License: [MIT](./LICENSE)
