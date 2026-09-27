# Phân tích ảnh hưởng của kích thước block đến độ thưa và độ chính xác

## 1. Thiết lập thí nghiệm

Thí nghiệm được thực hiện nhằm đánh giá ảnh hưởng của kích thước block trong phương pháp **block pruning**. Mô hình sử dụng trong thí nghiệm là **Llama-2**. Ma trận attention được chia thành các block không chồng lấn và thực hiện pruning trên từng block.

## 2. Phương pháp Block Pruning

Ma trận attention được chia thành các block không chồng lấn. Với mỗi block, tổng giá trị attention được tính theo từng hàng. Sau đó, một ngưỡng pruning được xác định.

Trong thí nghiệm này:

- Hệ số pruning: **α = 20**
- Ngưỡng pruning phụ thuộc vào độ dài chuỗi.
- Một block bị loại bỏ nếu tất cả các hàng trong block đều có giá trị nhỏ hơn ngưỡng pruning.

Thí nghiệm được chia thành ba hướng khảo sát:

- **Task A - Mở rộng theo hàng:** tăng kích thước block theo chiều hàng trong khi giữ chiều cột cố định.
- **Task B - Mở rộng theo cột:** tăng kích thước block theo chiều cột trong khi giữ chiều hàng cố định.
- **Task C - Mở rộng đồng thời hàng và cột:** thay đổi cả hai chiều, đồng thời khảo sát các cấu hình phù hợp cho triển khai phần cứng như **32×32**.

## 3. Chỉ số đánh giá

### 3.1. Độ thưa

Độ thưa cho biết tỷ lệ phần attention bị loại bỏ sau pruning.

### 3.2. Điểm LongBench

Chất lượng mô hình sau pruning được đánh giá trên ba tác vụ LongBench:

- **NarrativeQA:** đánh giá khả năng trả lời câu hỏi dựa trên văn bản dài dạng truyện.
- **Qasper:** đánh giá khả năng đọc hiểu và trả lời câu hỏi trên các bài báo khoa học.
- **GovReport:** đánh giá khả năng xử lý nội dung từ các báo cáo chính phủ dài.

### 3.3. Dense Score, Sparse Score và Score Loss

- **Dense Avg Score:** điểm trung bình của mô hình gốc khi chưa pruning.
- **Sparse Avg Score:** điểm trung bình sau khi áp dụng block pruning.
- **Score Loss:** mức thay đổi chất lượng so với dense baseline.

Cách đọc Score Loss:

- **Gần 0:** chất lượng sparse gần tương đương dense.
- **Dương:** sparse thấp hơn dense.
- **Âm:** sparse cao hơn dense trên tập đánh giá.

---

# 4. Task A - Mở rộng theo hàng

## 4.1. Kết quả

| Block   |   Độ thưa (%) |   Điểm dense TB |   Điểm sparse TB |   Score Loss TB |
|:--------|--------------:|----------------:|-----------------:|----------------:|
| 1x20    |     91.014273 |           11.89 |        11.856667 |        0.033333 |
| 2x20    |     89.403646 |           11.89 |        11.890000 |        0.000000 |
| 3x20    |     88.318674 |           11.89 |        11.956667 |       -0.066667 |
| 5x20    |     86.856361 |           11.89 |        11.970000 |       -0.080000 |
| 8x20    |     85.266101 |           11.89 |        11.926667 |       -0.036667 |
| 10x20   |     84.583689 |           11.89 |        12.030000 |       -0.140000 |
| 16x20   |     82.581427 |           11.89 |        11.960000 |       -0.070000 |
| 20x20   |     81.967743 |           11.89 |        11.926667 |       -0.036667 |
| 32x20   |     79.429765 |           11.89 |        11.956667 |       -0.066667 |
| 40x20   |     78.650097 |           11.89 |        11.893333 |       -0.003333 |
| 50x20   |     77.417196 |           11.89 |        11.880000 |        0.010000 |
| 64x20   |     75.695681 |           11.89 |        11.860000 |        0.030000 |
| 80x20   |     74.865449 |           11.89 |        11.870000 |        0.020000 |
| 100x20  |     73.421903 |           11.89 |        11.870000 |        0.020000 |
| 32x32   |     74.731240 |           11.89 |        11.906667 |       -0.016667 |

Khi tăng kích thước block theo chiều hàng, độ thưa giảm từ khoảng **91.01% với block 1×20** xuống **73.42% với block 100×20**. Điều này cho thấy block càng cao thì khả năng toàn bộ block thỏa điều kiện pruning càng giảm.

Trong khi đó, điểm LongBench vẫn dao động rất gần dense baseline **11.89**. Vì vậy, trong phạm vi thí nghiệm này, việc tăng kích thước block theo chiều hàng tác động mạnh hơn đến độ thưa so với chất lượng mô hình.

Cấu hình **32×32** đạt khoảng **74.73% độ thưa**, với **Sparse Avg Score = 11.9067** và **Score Loss ≈ -0.0167**.

![Độ thưa - Task A](images/task_a_sparsity.png)

![Score Loss - Task A](images/task_a_score_loss.png)

![Điểm LongBench - Task A](images/task_a_avg_score.png)

---

# 5. Task B - Mở rộng theo cột

## 5.1. Kết quả

| Block   |   Độ thưa (%) |   Điểm dense TB |   Điểm sparse TB |   Score Loss TB |
|:--------|--------------:|----------------:|-----------------:|----------------:|
| 3x3     |     97.740066 |           11.89 |        12.006667 |       -0.116667 |
| 3x5     |     96.284140 |           11.89 |        11.970000 |       -0.080000 |
| 3x10    |     93.088527 |           11.89 |        11.970000 |       -0.080000 |
| 3x15    |     90.723784 |           11.89 |        11.993333 |       -0.103333 |
| 3x20    |     88.318674 |           11.89 |        11.956667 |       -0.066667 |
| 3x30    |     84.697812 |           11.89 |        11.910000 |       -0.020000 |
| 3x40    |     81.496229 |           11.89 |        11.866667 |        0.023333 |
| 3x50    |     78.388524 |           11.89 |        11.966667 |       -0.076667 |
| 3x64    |     75.556160 |           11.89 |        11.903333 |       -0.013333 |
| 3x80    |     71.723694 |           11.89 |        11.930000 |       -0.040000 |
| 3x100   |     68.343068 |           11.89 |        11.923333 |       -0.033333 |
| 3x128   |     65.019047 |           11.89 |        11.940000 |       -0.050000 |
| 3x160   |     59.232893 |           11.89 |        11.923333 |       -0.033333 |
| 3x200   |     56.627875 |           11.89 |        11.910000 |       -0.020000 |
| 32x32   |     74.731240 |           11.89 |        11.906667 |       -0.016667 |

Khi tăng kích thước block theo chiều cột, độ thưa giảm từ khoảng **97.74% với block 3×3** xuống **56.63% với block 3×200**. Block càng rộng thì khả năng pruning càng giảm vì nhiều phần tử hơn phải đồng thời thỏa điều kiện loại bỏ.

Mặc dù độ thưa thay đổi lớn, điểm sparse vẫn duy trì gần dense baseline **11.89**. Kết quả cho thấy chiều cột có ảnh hưởng mạnh đến mức độ thưa, nhưng trong tập đánh giá này không gây suy giảm đáng kể về điểm LongBench.

![Độ thưa - Task B](images/task_b_sparsity.png)

![Score Loss - Task B](images/task_b_score_loss.png)

![Điểm LongBench - Task B](images/task_b_avg_score.png)

---

# 6. Task C - Mở rộng đồng thời hàng và cột

## 6.1. Kết quả

| Block   |   Độ thưa (%) |   Điểm dense TB |   Điểm sparse TB |   Score Loss TB |
|:--------|--------------:|----------------:|-----------------:|----------------:|
| 1x10    |     94.830000 |           11.89 |        11.950000 |       -0.060000 |
| 2x20    |     89.400000 |           11.89 |        11.890000 |        0.000000 |
| 3x20    |     88.320000 |           11.89 |        11.956700 |       -0.066700 |
| 4x32    |     83.070000 |           11.89 |        11.926700 |       -0.036700 |
| 8x32    |     80.500000 |           11.89 |        11.880000 |        0.010000 |
| 16x32   |     77.680000 |           11.89 |        11.960000 |       -0.070000 |
| 16x16   |     85.240000 |           11.89 |        12.040000 |       -0.150000 |
| 32x32   |     74.730000 |           11.89 |        11.906700 |       -0.016700 |
| 32x64   |     65.890000 |           11.89 |        11.916700 |       -0.026700 |
| 32x100  |     58.680000 |           11.89 |        11.930000 |       -0.040000 |
| 64x64   |     63.360000 |           11.89 |        11.910000 |       -0.020000 |
| 64x100  |     55.760000 |           11.89 |        11.926700 |       -0.036700 |
| 100x100 |     56.370000 |           11.89 |        11.850000 |        0.040000 |
| 128x128 |     53.447189 |           11.89 |        11.896667 |       -0.006667 |

Khi tăng kích thước block theo cả hai chiều, độ thưa giảm từ khoảng **94.83% với block 1×10** xuống **53.45% với block 128×128**. Block lớn hơn làm vùng attention cần được đánh giá rộng hơn, do đó khả năng loại bỏ toàn bộ block giảm.

Các cấu hình vẫn duy trì điểm sparse gần dense baseline **11.89**, với Score Loss nhỏ trong phần lớn trường hợp.

Cấu hình **32×32** đạt khoảng **74.73% độ thưa** và **Sparse Avg Score = 11.9067**. Đây là cấu hình đáng chú ý khi xét đồng thời khả năng pruning và sự tương thích với accelerator có mảng xử lý **32×32**.

![Độ thưa - Task C](images/task_c_sparsity.png)

![Score Loss - Task C](images/task_c_score_loss.png)

![Điểm LongBench - Task C](images/task_c_avg_score.png)

---

# 7. Nhận xét tổng quát

Kết quả của ba hướng khảo sát cho thấy xu hướng nhất quán: **kích thước block càng lớn thì độ thưa đạt được càng giảm**. Nguyên nhân là một block lớn chứa nhiều phần tử hơn, nên điều kiện để toàn bộ block bị loại bỏ trở nên khó thỏa mãn hơn.

Trong khi đó, điểm LongBench của các cấu hình sparse nhìn chung vẫn nằm rất gần dense baseline. Vì vậy, trong phạm vi dữ liệu đánh giá của báo cáo, thay đổi kích thước block ảnh hưởng rõ rệt đến **mức độ pruning** hơn là đến **chất lượng đầu ra của mô hình**.

Cấu hình **32×32** là một điểm cần quan tâm vì vừa duy trì chất lượng gần dense baseline, vừa phù hợp trực tiếp với kiến trúc accelerator 32×32.
